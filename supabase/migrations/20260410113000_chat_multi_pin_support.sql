-- Support multiple pinned messages per chat while preserving latest pin on chats.
create table if not exists public.chat_pinned_messages (
  chat_id uuid not null references public.chats (id) on delete cascade,
  message_id uuid not null references public.messages (id) on delete cascade,
  pinned_by uuid references public.users (id) on delete set null,
  pinned_at timestamptz not null default now(),
  primary key (chat_id, message_id)
);

create index if not exists chat_pinned_messages_chat_id_pinned_at_idx
  on public.chat_pinned_messages (chat_id, pinned_at desc);

alter table public.chat_pinned_messages enable row level security;

drop policy if exists chat_pinned_messages_select_participant on public.chat_pinned_messages;
create policy chat_pinned_messages_select_participant
on public.chat_pinned_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = chat_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
);

drop policy if exists chat_pinned_messages_insert_participant on public.chat_pinned_messages;
create policy chat_pinned_messages_insert_participant
on public.chat_pinned_messages
for insert
to authenticated
with check (
  exists (
    select 1
    from public.chats c
    where c.id = chat_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
  and exists (
    select 1
    from public.messages m
    where m.id = message_id and m.chat_id = chat_id
  )
);

drop policy if exists chat_pinned_messages_delete_participant on public.chat_pinned_messages;
create policy chat_pinned_messages_delete_participant
on public.chat_pinned_messages
for delete
to authenticated
using (
  exists (
    select 1
    from public.chats c
    where c.id = chat_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
);
