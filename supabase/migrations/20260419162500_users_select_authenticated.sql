-- Allow authenticated users to read user profiles.
-- Needed for discover/item detail owner name lookups.

drop policy if exists users_select_self on public.users;

create policy users_select_authenticated
on public.users
for select
to authenticated
using (true);
