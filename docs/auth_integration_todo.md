# Authentication Integration TODO

This document tracks the temporary bypasses added to test the chat and AI messaging flow before the login functionality was completed.
Once your teammate's login integration is ready, follow these steps to revert the hardcoded values and restore database security.

## 1. Revert Flutter App Hardcoding

### `lib/services/chat_service.dart`
Remove the hardcoded test IDs in `refreshCurrentUserId()` and restore the Supabase authentication fetch.

**Remove:**
```dart
  Future<int?> refreshCurrentUserId() async {
    // TESTING ONLY: Hardcoding user id to 1 and auth_user_id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    _cachedAuthUserId = '86369cf5-f4a3-458e-bbe8-8c957854efec';
    _cachedCurrentUserId = 1;
    return 1;
  }
```

**Restore to:**
```dart
  Future<int?> refreshCurrentUserId() async {
    final authUserId = SupabaseService.client.auth.currentUser?.id;
    if (authUserId == null) {
      _cachedAuthUserId = null;
      _cachedCurrentUserId = null;
      return null;
    }

    if (_cachedAuthUserId == authUserId && _cachedCurrentUserId != null) {
      return _cachedCurrentUserId;
    }

    final appUser = await _usersRepository.getByAuthUserId(authUserId);
    _cachedAuthUserId = authUserId;
    _cachedCurrentUserId = appUser?.id;
    return _cachedCurrentUserId;
  }
```

### `lib/repositories/ai_messages_repository.dart`
Remove the hardcoded `userId` in all AI message operations (`watchMessages()`, `fetchMessages()`, `insertMessage()`, `editMessage()`, `deleteMessage()`, `pinMessage()`, `unpinMessage()`, `listPinnedMessages()`).

**In `watchMessages()` and `insertMessage()`:**
Change:
```dart
// TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';
```
**Back to:**
```dart
final userId = _supabase.auth.currentUser?.id;
```

### `supabase/functions/ai_chat/index.ts`
Remove the hardcoded test `userId` bypass and restore the strict `Unauthorized` error throw when a user is absent.

**Replace:**
```typescript
    const { data: { user } } = await supabaseClient.auth.getUser()

    // TESTING ONLY: Bypass auth check and hardcode user ID
    const userId = user?.id || '86369cf5-f4a3-458e-bbe8-8c957854efec';
```
**With the fully secure check:**
```typescript
    const { data: { user } } = await supabaseClient.auth.getUser()

    if (!user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const userId = user.id;
```

## 2. Restore Supabase Security Policies (RLS)

Since you executed commands to grant the anonymous (`anon`) role access to your tables and conditionally disabled RLS during testing, you need to revoke those privileges in your Supabase SQL Editor.

Run the following SQL snippet exactly when the real login is working:

```sql
-- 1. Re-enable Row Level Security (If you strictly disabled it via ALTER TABLE)
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_message_pins ENABLE ROW LEVEL SECURITY;

-- 2. Revoke full table access from the anonymous role
REVOKE ALL ON TABLE public.chats FROM anon;
REVOKE ALL ON TABLE public.messages FROM anon;
REVOKE ALL ON TABLE public.ai_messages FROM anon;
REVOKE ALL ON TABLE public.ai_message_pins FROM anon;
REVOKE USAGE ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- 3. Drop the anonymous testing policies
DROP POLICY IF EXISTS "Anon test read ai pins" ON public.ai_message_pins;
DROP POLICY IF EXISTS "Anon test write ai pins" ON public.ai_message_pins;
DROP POLICY IF EXISTS "Anon test update ai pins" ON public.ai_message_pins;
DROP POLICY IF EXISTS "Anon test delete ai pins" ON public.ai_message_pins;
REVOKE SELECT ON TABLE public.users FROM anon;
REVOKE SELECT ON TABLE public.items FROM anon;
```

## 3. Realtime Messaging Setup (Supabase Dashboard)

For AI messages (or regular chats) to dynamically appear on the screen without having to pull-to-refresh or re-opening the page, the corresponding table must be added to the `supabase_realtime` publication.

If real-time isn't working for the AI chat right now, run this in your **Supabase SQL Editor**:
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.ai_messages;
```
