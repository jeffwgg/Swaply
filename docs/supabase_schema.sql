-- Swaply schema for Supabase (PostgreSQL)
-- Generated from docs/database-schema.md
--
-- NOTE: This is the base schema. For chat module enhancements (read_at, edited_at,
-- deleted_at fields, message pinning, etc.), see migration files in supabase/migrations/
-- starting from 20260407143000_chat_realtime_upgrade.sql

create extension if not exists pgcrypto;

create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  email text not null unique,
  profile_image text,
  created_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null,
  price numeric(12, 2),
  listing_type text not null check (listing_type in ('sell', 'trade', 'both')),
  owner_id uuid not null references public.users (id) on delete cascade,
  status text not null default 'available' check (status in ('available', 'completed')),
  category text not null,
  image_url text,
  condition text not null check (condition in ('new', 'used')),
  created_at timestamptz not null default now()
);

create table if not exists public.transaction_requests (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  requester_id uuid not null references public.users (id) on delete cascade,
  type text not null check (type in ('purchase', 'trade')),
  offered_price numeric(12, 2),
  offered_item_id uuid references public.items (id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  constraint transaction_request_type_rule check (
    (type = 'purchase' and offered_price is not null and offered_item_id is null) or
    (type = 'trade' and offered_item_id is not null and offered_price is null)
  )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  user1_id uuid not null references public.users (id) on delete cascade,
  user2_id uuid not null references public.users (id) on delete cascade,
  item_id uuid references public.items (id) on delete set null,
  last_message text,
  updated_at timestamptz not null default now(),
  constraint chat_user_pair_not_same check (user1_id <> user2_id)
);

create unique index if not exists chats_user_pair_unique_idx
on public.chats (
  least(user1_id, user2_id),
  greatest(user1_id, user2_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.users (id) on delete cascade,
  content text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists items_owner_id_idx on public.items (owner_id);
create index if not exists transaction_requests_item_id_idx on public.transaction_requests (item_id);
create index if not exists transaction_requests_requester_id_idx on public.transaction_requests (requester_id);
create index if not exists messages_chat_id_idx on public.messages (chat_id);

create or replace function public.handle_chat_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_chats_updated_at on public.chats;
create trigger trg_chats_updated_at
before update on public.chats
for each row
execute function public.handle_chat_updated_at();

create or replace function public.handle_message_insert_update_chat()
returns trigger
language plpgsql
as $$
begin
  update public.chats
  set
    last_message = new.content,
    updated_at = now()
  where id = new.chat_id;

  return new;
end;
$$;

drop trigger if exists trg_messages_update_chat on public.messages;
create trigger trg_messages_update_chat
after insert on public.messages
for each row
execute function public.handle_message_insert_update_chat();

alter table public.users enable row level security;
alter table public.items enable row level security;
alter table public.transaction_requests enable row level security;
alter table public.chats enable row level security;
alter table public.messages enable row level security;

drop policy if exists users_select_self on public.users;
create policy users_select_self
on public.users
for select
to authenticated
using (auth.uid() = id);

drop policy if exists users_upsert_self on public.users;
create policy users_upsert_self
on public.users
for all
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists items_select_all on public.items;
create policy items_select_all
on public.items
for select
to authenticated
using (true);

drop policy if exists items_owner_write on public.items;
create policy items_owner_write
on public.items
for all
to authenticated
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

drop policy if exists transaction_requests_access_participants on public.transaction_requests;
create policy transaction_requests_access_participants
on public.transaction_requests
for select
to authenticated
using (
  auth.uid() = requester_id or
  exists (
    select 1
    from public.items i
    where i.id = item_id and i.owner_id = auth.uid()
  )
);

drop policy if exists transaction_requests_create_requester on public.transaction_requests;
create policy transaction_requests_create_requester
on public.transaction_requests
for insert
to authenticated
with check (auth.uid() = requester_id);

drop policy if exists transaction_requests_update_owner_or_requester on public.transaction_requests;
create policy transaction_requests_update_owner_or_requester
on public.transaction_requests
for update
to authenticated
using (
  auth.uid() = requester_id or
  exists (
    select 1
    from public.items i
    where i.id = item_id and i.owner_id = auth.uid()
  )
)
with check (
  auth.uid() = requester_id or
  exists (
    select 1
    from public.items i
    where i.id = item_id and i.owner_id = auth.uid()
  )
);

drop policy if exists chats_select_participants on public.chats;
create policy chats_select_participants
on public.chats
for select
to authenticated
using (auth.uid() = user1_id or auth.uid() = user2_id);

drop policy if exists chats_insert_participants on public.chats;
create policy chats_insert_participants
on public.chats
for insert
to authenticated
with check (auth.uid() = user1_id or auth.uid() = user2_id);

drop policy if exists chats_update_participants on public.chats;
create policy chats_update_participants
on public.chats
for update
to authenticated
using (auth.uid() = user1_id or auth.uid() = user2_id)
with check (auth.uid() = user1_id or auth.uid() = user2_id);

drop policy if exists messages_select_participants on public.messages;
create policy messages_select_participants
on public.messages
for select
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = chat_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
);

drop policy if exists messages_insert_sender_participant on public.messages;
create policy messages_insert_sender_participant
on public.messages
for insert
to authenticated
with check (
  sender_id = auth.uid() and
  exists (
    select 1
    from public.chats c
    where c.id = chat_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
);

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
