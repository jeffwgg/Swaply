-- Dev bridge for message edit/delete when auth UI is not integrated yet.
-- Adds:
-- 1) 3-minute edit window (same as delete window)
-- 2) Effective actor fallback from custom setting app.current_user_id
-- 3) RPCs to set actor context and perform update through existing trigger rules

create or replace function public.get_effective_actor_id()
returns uuid
language plpgsql
stable
as $$
declare
  v_actor_text text;
begin
  if auth.uid() is not null then
    return auth.uid();
  end if;

  v_actor_text := current_setting('app.current_user_id', true);
  if v_actor_text is null or btrim(v_actor_text) = '' then
    return null;
  end if;

  return v_actor_text::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

create or replace function public.handle_message_before_update()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid;
  v_username text;
  v_content_changed boolean := new.content is distinct from old.content;
  v_deleted_changed boolean := new.deleted_at is distinct from old.deleted_at;
  v_read_changed boolean := new.read_at is distinct from old.read_at;
begin
  v_actor := public.get_effective_actor_id();

  if new.chat_id <> old.chat_id
    or new.sender_id <> old.sender_id
    or new.created_at <> old.created_at then
    raise exception 'Immutable message columns cannot be changed';
  end if;

  if old.deleted_at is not null then
    raise exception 'Deleted messages cannot be modified';
  end if;

  if v_deleted_changed then
    if new.deleted_at is null then
      raise exception 'Deleted message cannot be restored';
    end if;

    if v_actor is null or v_actor <> old.sender_id then
      raise exception 'Only the sender can delete this message';
    end if;

    if now() - old.created_at > interval '3 minutes' then
      raise exception 'Delete window expired. Message can only be deleted within 3 minutes';
    end if;

    select u.username into v_username
    from public.users u
    where u.id = old.sender_id;

    new.deleted_by := old.sender_id;
    new.deleted_at := coalesce(new.deleted_at, now());
    new.content := coalesce(v_username, 'User') || ' deleted a msg';
    new.edited_at := old.edited_at;

    return new;
  end if;

  if v_content_changed then
    if v_actor is null or v_actor <> old.sender_id then
      raise exception 'Only the sender can edit this message';
    end if;

    if now() - old.created_at > interval '3 minutes' then
      raise exception 'Edit window expired. Message can only be edited within 3 minutes';
    end if;

    if btrim(new.content) = '' then
      raise exception 'Message content cannot be empty';
    end if;

    new.edited_at := now();
    return new;
  end if;

  if v_read_changed then
    if v_actor is null or v_actor = old.sender_id then
      raise exception 'Only the receiver can mark this message as read';
    end if;

    if old.read_at is not null then
      new.read_at := old.read_at;
    elseif new.read_at is null then
      new.read_at := now();
    end if;

    return new;
  end if;

  return new;
end;
$$;

create or replace function public.edit_message_as_user(
  p_message_id uuid,
  p_actor_id uuid,
  p_content text
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.messages;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;

  perform set_config('app.current_user_id', p_actor_id::text, true);

  update public.messages
  set content = p_content
  where id = p_message_id
  returning * into v_row;

  if not found then
    raise exception 'Message not found';
  end if;

  return v_row;
end;
$$;

create or replace function public.delete_message_as_user(
  p_message_id uuid,
  p_actor_id uuid
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.messages;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;

  perform set_config('app.current_user_id', p_actor_id::text, true);

  update public.messages
  set deleted_at = now()
  where id = p_message_id
  returning * into v_row;

  if not found then
    raise exception 'Message not found';
  end if;

  return v_row;
end;
$$;

grant execute on function public.edit_message_as_user(uuid, uuid, text) to anon, authenticated;
grant execute on function public.delete_message_as_user(uuid, uuid) to anon, authenticated;
