-- Chat and message upgrade for realtime inbox/conversation flow
-- Rules implemented:
-- 1) One chat per normalized user pair per item
-- 2) Item-linked chats only (item_id required)
-- 3) Message read tracking with read_at
-- 4) Edit support for sender
-- 5) Delete support for sender within 3 minutes, shown as "<username> deleted a msg"

-- Enforce item-linked chats only.
do $$
begin
  if exists (select 1 from public.chats where item_id is null) then
    raise exception 'Cannot enforce item-linked chat because chats.item_id has NULL values.';
  end if;
end
$$;

alter table public.chats
  alter column item_id set not null;

-- Replace unique rule: now unique by normalized user pair + item.
drop index if exists public.chats_user_pair_unique_idx;

create unique index if not exists chats_user_pair_item_unique_idx
on public.chats (
  least(user1_id, user2_id),
  greatest(user1_id, user2_id),
  item_id
);

-- Message lifecycle columns.
alter table public.messages
  add column if not exists read_at timestamptz,
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.users (id) on delete set null;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'messages'
      and column_name = 'is_read'
  ) then
    execute 'update public.messages set read_at = created_at where read_at is null and coalesce(is_read, false) = true';

    execute 'alter table public.messages drop column if exists is_read';
  end if;
end
$$;

create index if not exists messages_chat_created_idx
  on public.messages (chat_id, created_at);

create index if not exists chats_updated_at_idx
  on public.chats (updated_at desc);

create or replace function public.refresh_chat_last_message(
  p_chat_id uuid,
  p_touch_updated_at boolean default false
)
returns void
language plpgsql
as $$
declare
  v_last_message text;
begin
  select m.content
    into v_last_message
  from public.messages m
  where m.chat_id = p_chat_id
  order by m.created_at desc
  limit 1;

  if p_touch_updated_at then
    update public.chats
    set
      last_message = v_last_message,
      updated_at = now()
    where id = p_chat_id;
  else
    update public.chats
    set last_message = v_last_message
    where id = p_chat_id;
  end if;
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
  v_actor := auth.uid();

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

create or replace function public.handle_message_after_insert()
returns trigger
language plpgsql
as $$
begin
  perform public.refresh_chat_last_message(new.chat_id, true);
  return new;
end;
$$;

create or replace function public.handle_message_after_update()
returns trigger
language plpgsql
as $$
declare
  v_latest_id uuid;
begin
  if new.content is distinct from old.content then
    select m.id
      into v_latest_id
    from public.messages m
    where m.chat_id = new.chat_id
    order by m.created_at desc
    limit 1;

    if v_latest_id = new.id then
      perform public.refresh_chat_last_message(new.chat_id, false);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_messages_before_update on public.messages;
create trigger trg_messages_before_update
before update on public.messages
for each row
execute function public.handle_message_before_update();

drop trigger if exists trg_messages_update_chat on public.messages;
create trigger trg_messages_update_chat
after insert on public.messages
for each row
execute function public.handle_message_after_insert();

drop trigger if exists trg_messages_after_update_chat on public.messages;
create trigger trg_messages_after_update_chat
after update on public.messages
for each row
execute function public.handle_message_after_update();

-- Create/get helper for client flow (item-linked only).
create or replace function public.create_or_get_item_chat(
  p_user_a uuid,
  p_user_b uuid,
  p_item_id uuid
)
returns public.chats
language plpgsql
security definer
set search_path = public
as $$
declare
  v_low uuid;
  v_high uuid;
  v_chat public.chats;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if p_user_a = p_user_b then
    raise exception 'A chat requires two different users';
  end if;

  if p_item_id is null then
    raise exception 'item_id is required';
  end if;

  if auth.uid() <> p_user_a and auth.uid() <> p_user_b then
    raise exception 'Authenticated user must be one of the chat participants';
  end if;

  v_low := least(p_user_a, p_user_b);
  v_high := greatest(p_user_a, p_user_b);

  select c.*
    into v_chat
  from public.chats c
  where least(c.user1_id, c.user2_id) = v_low
    and greatest(c.user1_id, c.user2_id) = v_high
    and c.item_id = p_item_id
  limit 1;

  if found then
    return v_chat;
  end if;

  insert into public.chats (user1_id, user2_id, item_id)
  values (v_low, v_high, p_item_id)
  returning * into v_chat;

  return v_chat;
exception
  when unique_violation then
    select c.*
      into v_chat
    from public.chats c
    where least(c.user1_id, c.user2_id) = v_low
      and greatest(c.user1_id, c.user2_id) = v_high
      and c.item_id = p_item_id
    limit 1;

    return v_chat;
end;
$$;

grant execute on function public.create_or_get_item_chat(uuid, uuid, uuid) to authenticated;

-- Tighten policies around message updates.
drop policy if exists messages_update_participant on public.messages;

create policy messages_update_participant
on public.messages
for update
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = chat_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.chats c
    where c.id = chat_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
);
