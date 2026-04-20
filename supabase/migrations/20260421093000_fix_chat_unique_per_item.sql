-- Ensure one chat per (normalized user pair + item_id)
-- This fixes cases where different items between the same two users collapse into one chat.

-- Remove legacy pair-only uniqueness if it exists.
drop index if exists public.chats_user_pair_unique_idx;

-- Enforce item-linked uniqueness.
create unique index if not exists chats_user_pair_item_unique_idx
on public.chats (
  least(user1_id, user2_id),
  greatest(user1_id, user2_id),
  item_id
);

-- Keep item required for item-linked chats.
alter table public.chats
  alter column item_id set not null;

-- Ensure RPC follows the same key semantics.
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

  return (
    with existing as (
      select c.*
      from public.chats c
      where least(c.user1_id, c.user2_id) = v_low
        and greatest(c.user1_id, c.user2_id) = v_high
        and c.item_id = p_item_id
      limit 1
    ), inserted as (
      insert into public.chats (user1_id, user2_id, item_id)
      select v_low, v_high, p_item_id
      where not exists (select 1 from existing)
      returning *
    )
    select * from existing
    union all
    select * from inserted
    limit 1
  );
exception
  when unique_violation then
    return (
      select c
      from public.chats c
      where least(c.user1_id, c.user2_id) = v_low
        and greatest(c.user1_id, c.user2_id) = v_high
        and c.item_id = p_item_id
      limit 1
    );
end;
$$;

grant execute on function public.create_or_get_item_chat(uuid, uuid, uuid) to authenticated;

-- Ask PostgREST to refresh function metadata cache.
select pg_notify('pgrst', 'reload schema');
