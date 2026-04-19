begin;

create extension if not exists pgcrypto;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.users (id) on delete cascade,
  actor_id uuid references public.users (id) on delete set null,
  type text not null check (type in ('chat', 'trade', 'general')),
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on table public.notifications to authenticated;
grant all privileges on table public.notifications to service_role;

create index if not exists notifications_recipient_created_idx
  on public.notifications (recipient_id, created_at desc);

create index if not exists notifications_recipient_unread_idx
  on public.notifications (recipient_id, is_read, created_at desc);

create or replace function public.notifications_set_read_at()
returns trigger
language plpgsql
as $$
begin
  if new.is_read and (old.is_read is distinct from true) and new.read_at is null then
    new.read_at := now();
  elsif not new.is_read then
    new.read_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notifications_set_read_at on public.notifications;
create trigger trg_notifications_set_read_at
before update on public.notifications
for each row
execute function public.notifications_set_read_at();

alter table public.notifications enable row level security;

drop policy if exists notifications_select_recipient on public.notifications;
create policy notifications_select_recipient
on public.notifications
for select
to authenticated
using (auth.uid() = recipient_id);

drop policy if exists notifications_insert_self on public.notifications;
create policy notifications_insert_self
on public.notifications
for insert
to authenticated
with check (
  auth.uid() = recipient_id
  and (actor_id is null or actor_id = auth.uid())
);

drop policy if exists notifications_update_recipient on public.notifications;
create policy notifications_update_recipient
on public.notifications
for update
to authenticated
using (auth.uid() = recipient_id)
with check (auth.uid() = recipient_id);

drop policy if exists notifications_delete_recipient on public.notifications;
create policy notifications_delete_recipient
on public.notifications
for delete
to authenticated
using (auth.uid() = recipient_id);

do $$
begin
  begin
    alter publication supabase_realtime add table public.notifications;
  exception
    when duplicate_object then
      null;
  end;
end
$$;

commit;
