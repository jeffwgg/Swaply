-- Dev RPC bridge for chat pin/read features when app uses profile-selected user IDs.
-- These functions validate participant access using p_actor_id and bypass direct table RLS.

create or replace function public.pin_message_as_user(
  p_chat_id uuid,
  p_message_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;

  select exists (
    select 1
    from public.chats c
    join public.messages m on m.id = p_message_id and m.chat_id = c.id
    where c.id = p_chat_id
      and (c.user1_id = p_actor_id or c.user2_id = p_actor_id)
  ) into v_exists;

  if not v_exists then
    raise exception 'Not allowed to pin this message';
  end if;

  insert into public.chat_pinned_messages (chat_id, message_id, pinned_by)
  values (p_chat_id, p_message_id, p_actor_id)
  on conflict (chat_id, message_id)
  do update set pinned_at = now(), pinned_by = excluded.pinned_by;

  update public.chats
  set
    pinned_message_id = p_message_id,
    pinned_at = now()
  where id = p_chat_id;
end;
$$;

create or replace function public.unpin_message_as_user(
  p_chat_id uuid,
  p_message_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_latest record;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;

  select exists (
    select 1
    from public.chats c
    where c.id = p_chat_id
      and (c.user1_id = p_actor_id or c.user2_id = p_actor_id)
  ) into v_exists;

  if not v_exists then
    raise exception 'Not allowed to unpin in this chat';
  end if;

  delete from public.chat_pinned_messages
  where chat_id = p_chat_id and message_id = p_message_id;

  select message_id, pinned_at
    into v_latest
  from public.chat_pinned_messages
  where chat_id = p_chat_id
  order by pinned_at desc
  limit 1;

  update public.chats
  set
    pinned_message_id = case when v_latest is null then null else v_latest.message_id end,
    pinned_at = case when v_latest is null then null else v_latest.pinned_at end
  where id = p_chat_id;
end;
$$;

create or replace function public.list_pinned_messages_as_user(
  p_chat_id uuid,
  p_actor_id uuid
)
returns setof public.chat_pinned_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;

  select exists (
    select 1
    from public.chats c
    where c.id = p_chat_id
      and (c.user1_id = p_actor_id or c.user2_id = p_actor_id)
  ) into v_exists;

  if not v_exists then
    raise exception 'Not allowed to view pins in this chat';
  end if;

  return query
  select p.*
  from public.chat_pinned_messages p
  where p.chat_id = p_chat_id
  order by p.pinned_at desc;
end;
$$;

create or replace function public.mark_chat_as_read_as_user(
  p_chat_id uuid,
  p_actor_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_count integer;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;

  select exists (
    select 1
    from public.chats c
    where c.id = p_chat_id
      and (c.user1_id = p_actor_id or c.user2_id = p_actor_id)
  ) into v_exists;

  if not v_exists then
    raise exception 'Not allowed to read this chat';
  end if;

  perform set_config('app.current_user_id', p_actor_id::text, true);

  update public.messages
  set read_at = now()
  where chat_id = p_chat_id
    and sender_id <> p_actor_id
    and read_at is null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.pin_message_as_user(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.unpin_message_as_user(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.list_pinned_messages_as_user(uuid, uuid) to anon, authenticated;
grant execute on function public.mark_chat_as_read_as_user(uuid, uuid) to anon, authenticated;
