-- Add chat-level pinned message so both participants see the same pinned item.
alter table public.chats
  add column if not exists pinned_message_id uuid references public.messages (id) on delete set null,
  add column if not exists pinned_at timestamptz;

create index if not exists chats_pinned_message_id_idx
  on public.chats (pinned_message_id);

-- Ensure only chat participants can pin/unpin within their chat.
drop policy if exists chats_update_participant on public.chats;
create policy chats_update_participant
on public.chats
for update
to authenticated
using (auth.uid() = user1_id or auth.uid() = user2_id)
with check (auth.uid() = user1_id or auth.uid() = user2_id);
