# Chat RLS and Testing Reference

## 1. Purpose

This reference explains:

1. The Row Level Security (RLS) policies created in migration 1.
2. How to test chat and messages now, even if the item creation UI is not ready.

Related migrations:

- `supabase/migrations/20260324131912_init_schema.sql`
- `supabase/migrations/20260407143000_chat_realtime_upgrade.sql`

---

## 2. What RLS Means

RLS (Row Level Security) controls access per row.

- `using (...)`: which existing rows a user can read/update/delete.
- `with check (...)`: which new row values are allowed during insert/update.
- `to authenticated`: applies to logged-in users.

---

## 3. Migration 1 Policy Reference

### 3.1 users

#### users_select_self
- Table: `public.users`
- Action: `select`
- Rule: user can read only own row (`auth.uid() = id`)

#### users_upsert_self
- Table: `public.users`
- Action: `all`
- Rule: user can write only own row (`auth.uid() = id`)

### 3.2 items

#### items_select_all
- Table: `public.items`
- Action: `select`
- Rule: any authenticated user can read all items (`using (true)`)

#### items_owner_write
- Table: `public.items`
- Action: `all`
- Rule: only owner can write (`auth.uid() = owner_id`)

### 3.3 transaction_requests

#### transaction_requests_access_participants
- Action: `select`
- Rule: requester OR target item owner can read

#### transaction_requests_create_requester
- Action: `insert`
- Rule: only requester can create (`auth.uid() = requester_id`)

#### transaction_requests_update_owner_or_requester
- Action: `update`
- Rule: requester OR target item owner can update

### 3.4 chats

#### chats_select_participants
- Action: `select`
- Rule: only participants (`user1_id` or `user2_id`)

#### chats_insert_participants
- Action: `insert`
- Rule: creator must be a participant

#### chats_update_participants
- Action: `update`
- Rule: only participants can update

### 3.5 messages

#### messages_select_participants
- Action: `select`
- Rule: user must belong to parent chat

#### messages_insert_sender_participant
- Action: `insert`
- Rule: sender must be `auth.uid()` and must be chat participant

#### messages_update_participant
- Action: `update`
- Rule: chat participants can update
- Note: migration 2 trigger adds stricter behavior checks (sender-only edit/delete, 3-minute delete, receiver-only read receipt)

---

## 4. What Migration 2 Changed for Chat Safety

Migration 2 (`20260407143000_chat_realtime_upgrade.sql`) adds:

1. Item-linked chat only (`chats.item_id` is NOT NULL).
2. Unique chat key is now user pair + item.
3. Message lifecycle fields: `read_at`, `edited_at`, `deleted_at`, `deleted_by`.
4. Trigger-enforced rules:
   - sender-only edit
   - sender-only delete
   - delete allowed only within 3 minutes
   - delete is soft-delete and content becomes `"<username> deleted a msg"`
   - receiver-only read receipt updates
5. `create_or_get_item_chat` RPC for safe chat creation.

---

## 5. How To Test Chat Before Item UI Is Ready

Because chat now requires `item_id`, you need at least one item row first.

### Option A (Recommended): create test item and chat directly in Supabase SQL editor

Run this SQL in Supabase SQL Editor (adjust IDs/emails if needed):

```sql
-- 1) Ensure two users exist in public.users.
select id, username, email from public.users order by created_at desc;

-- Example demo IDs currently in project:
-- 11111111-1111-4111-8111-111111111111 (Member 1001)
-- 22222222-2222-4222-8222-222222222222 (Member 1002)

-- 2) Create one test item owned by Member 1001.
insert into public.items (
  title,
  description,
  price,
  listing_type,
  owner_id,
  status,
  category,
  image_url,
  condition
)
values (
  'Test Camera',
  'Temporary item for chat testing',
  120.00,
  'sell',
  '11111111-1111-4111-8111-111111111111',
  'available',
  'Electronics',
  null,
  'used'
)
returning id;
```

Then create chat for that item:

```sql
-- Replace ITEM_ID_HERE from previous result.
insert into public.chats (user1_id, user2_id, item_id)
values (
  least('11111111-1111-4111-8111-111111111111'::uuid, '22222222-2222-4222-8222-222222222222'::uuid),
  greatest('11111111-1111-4111-8111-111111111111'::uuid, '22222222-2222-4222-8222-222222222222'::uuid),
  'ITEM_ID_HERE'::uuid
)
on conflict do nothing
returning id;
```

### Option B: seed item in a migration

Create a small seed migration inserting one test item and one test chat. Keep it only for development.

---

## 6. App Testing Steps With Current Temporary Profile Login

1. Open Profile tab.
2. Choose user by tapping one of the listed users (or paste UUID manually).
3. Open Chat tab.
4. Verify inbox and messages load for that selected user.

To simulate two-party chat:

1. Choose Member 1001 in Profile, send a message.
2. Switch Profile to Member 1002.
3. Open Chat and check realtime delivery/read status behavior.

---

## 7. Important Limitation Right Now

Your temporary Profile-based user switch does not create a real Supabase auth session.

This matters because trigger logic uses `auth.uid()` for strict rules.

- Basic listing and insert may work in relaxed/dev policy mode.
- Strict sender/receiver enforcement is fully reliable only with real authenticated session.

For full production behavior testing, add real auth sign-in flow (email/password, OTP, etc.) as soon as possible.
