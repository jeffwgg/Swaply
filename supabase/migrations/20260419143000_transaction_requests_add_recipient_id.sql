-- Add recipient_id to transaction_requests for immutable participant history
-- and simpler querying without joining items.

begin;

alter table public.transaction_requests
  add column if not exists recipient_id uuid;

-- Backfill from current item owner.
update public.transaction_requests tr
set recipient_id = i.owner_id
from public.items i
where tr.item_id = i.id
  and tr.recipient_id is null;

-- Keep recipient immutable and auto-populated at insert-time when omitted.
create or replace function public.set_transaction_request_recipient()
returns trigger
language plpgsql
as $$
begin
  if new.recipient_id is null then
    select owner_id into new.recipient_id
    from public.items
    where id = new.item_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_transaction_requests_set_recipient on public.transaction_requests;
create trigger trg_transaction_requests_set_recipient
before insert on public.transaction_requests
for each row
execute function public.set_transaction_request_recipient();

alter table public.transaction_requests
  alter column recipient_id set not null;

alter table public.transaction_requests
  drop constraint if exists transaction_requests_recipient_id_fkey,
  add constraint transaction_requests_recipient_id_fkey
    foreign key (recipient_id)
    references public.users (id)
    on delete cascade;

create index if not exists transaction_requests_recipient_id_idx
on public.transaction_requests (recipient_id);

-- RLS update: allow access/update for requester and recipient directly.
drop policy if exists transaction_requests_access_participants on public.transaction_requests;
create policy transaction_requests_access_participants
on public.transaction_requests
for select
to authenticated
using (auth.uid() = requester_id or auth.uid() = recipient_id);

drop policy if exists transaction_requests_update_owner_or_requester on public.transaction_requests;
create policy transaction_requests_update_owner_or_requester
on public.transaction_requests
for update
to authenticated
using (auth.uid() = requester_id or auth.uid() = recipient_id)
with check (auth.uid() = requester_id or auth.uid() = recipient_id);

commit;
