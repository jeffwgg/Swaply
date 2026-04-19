-- Chat media storage bucket and access policies.
-- Used by chat photo and voice attachment messages.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-media',
  'chat-media',
  true,
  52428800,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'audio/mp4',
    'audio/m4a',
    'audio/aac'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "chat_media_public_read" on storage.objects;
create policy "chat_media_public_read"
on storage.objects
for select
to public
using (bucket_id = 'chat-media');

drop policy if exists "chat_media_auth_upload" on storage.objects;
create policy "chat_media_auth_upload"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'chat-media');

drop policy if exists "chat_media_owner_update" on storage.objects;
create policy "chat_media_owner_update"
on storage.objects
for update
to authenticated
using (bucket_id = 'chat-media' and owner = auth.uid())
with check (bucket_id = 'chat-media' and owner = auth.uid());

drop policy if exists "chat_media_owner_delete" on storage.objects;
create policy "chat_media_owner_delete"
on storage.objects
for delete
to authenticated
using (bucket_id = 'chat-media' and owner = auth.uid());
