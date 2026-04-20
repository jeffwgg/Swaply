-- Standalone function patch: create_or_get_item_chat
-- Safe to run independently when full migration status is unknown.

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

  if exists (
    select 1
    from public.chats c
    where least(c.user1_id, c.user2_id) = v_low
      and greatest(c.user1_id, c.user2_id) = v_high
      and c.item_id = p_item_id
  ) then
    return (
      select c
      from public.chats c
      where least(c.user1_id, c.user2_id) = v_low
        and greatest(c.user1_id, c.user2_id) = v_high
        and c.item_id = p_item_id
      limit 1
    );
  end if;

  return (
    with inserted as (
      insert into public.chats (user1_id, user2_id, item_id)
      values (v_low, v_high, p_item_id)
      returning *
    )
    select inserted
    from inserted
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
