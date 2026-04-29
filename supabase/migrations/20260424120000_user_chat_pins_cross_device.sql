begin;

create table if not exists public.user_chat_pins (
  user_id uuid not null,
  chat_id integer not null,
  pinned_at timestamptz not null default now(),
  constraint user_chat_pins_pkey primary key (user_id, chat_id),
  constraint user_chat_pins_user_id_fkey
    foreign key (user_id) references public.users (id) on delete cascade,
  constraint user_chat_pins_chat_id_fkey
    foreign key (chat_id) references public.chats (id) on delete cascade
);

create index if not exists user_chat_pins_user_pinned_at_idx
  on public.user_chat_pins (user_id, pinned_at desc);

alter table public.user_chat_pins enable row level security;

drop policy if exists user_chat_pins_select_self on public.user_chat_pins;
create policy user_chat_pins_select_self
on public.user_chat_pins
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists user_chat_pins_insert_self on public.user_chat_pins;
create policy user_chat_pins_insert_self
on public.user_chat_pins
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists user_chat_pins_delete_self on public.user_chat_pins;
create policy user_chat_pins_delete_self
on public.user_chat_pins
for delete
to authenticated
using (auth.uid() = user_id);

do $$
begin
  begin
    alter publication supabase_realtime add table public.user_chat_pins;
  exception
    when duplicate_object then
      null;
  end;
end $$;

commit;

