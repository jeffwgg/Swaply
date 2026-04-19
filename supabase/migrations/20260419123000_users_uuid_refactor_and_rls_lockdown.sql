-- Migrate user references from integer users.id to UUID users.id,
-- then lock down chat/AI access with authenticated-only RLS.

begin;

-- Drop policy dependencies up-front so column swaps do not fail.
DROP POLICY IF EXISTS items_owner_write ON public.items;
DROP POLICY IF EXISTS transaction_requests_access_participants ON public.transaction_requests;
DROP POLICY IF EXISTS transaction_requests_create_requester ON public.transaction_requests;
DROP POLICY IF EXISTS transaction_requests_update_owner_or_requester ON public.transaction_requests;
DROP POLICY IF EXISTS chats_select_participants ON public.chats;
DROP POLICY IF EXISTS chats_insert_participants ON public.chats;
DROP POLICY IF EXISTS chats_update_participants ON public.chats;
DROP POLICY IF EXISTS messages_select_participants ON public.messages;
DROP POLICY IF EXISTS messages_insert_sender_participant ON public.messages;
DROP POLICY IF EXISTS messages_update_participant ON public.messages;
DROP POLICY IF EXISTS users_select_self ON public.users;
DROP POLICY IF EXISTS users_upsert_self ON public.users;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'chat_pinned_messages'
  ) THEN
    EXECUTE 'DROP POLICY IF EXISTS chat_pinned_messages_select_participants ON public.chat_pinned_messages';
    EXECUTE 'DROP POLICY IF EXISTS chat_pinned_messages_insert_participants ON public.chat_pinned_messages';
    EXECUTE 'DROP POLICY IF EXISTS chat_pinned_messages_delete_participants ON public.chat_pinned_messages';
  END IF;
END $$;

-- 1) Convert all user foreign key columns from int -> uuid (via users.auth_user_id).

-- items.owner_id
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'items'
      AND column_name = 'owner_id'
      AND data_type IN ('integer', 'bigint', 'smallint')
  ) THEN
    ALTER TABLE public.items ADD COLUMN IF NOT EXISTS owner_id_uuid uuid;

    UPDATE public.items i
    SET owner_id_uuid = u.auth_user_id
    FROM public.users u
    WHERE i.owner_id = u.id
      AND i.owner_id_uuid IS NULL;

    ALTER TABLE public.items DROP CONSTRAINT IF EXISTS items_owner_id_fkey;
    ALTER TABLE public.items ALTER COLUMN owner_id_uuid SET NOT NULL;
    ALTER TABLE public.items DROP COLUMN owner_id;
    ALTER TABLE public.items RENAME COLUMN owner_id_uuid TO owner_id;
  END IF;
END $$;

-- transaction_requests.requester_id
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'transaction_requests'
      AND column_name = 'requester_id'
      AND data_type IN ('integer', 'bigint', 'smallint')
  ) THEN
    ALTER TABLE public.transaction_requests ADD COLUMN IF NOT EXISTS requester_id_uuid uuid;

    UPDATE public.transaction_requests tr
    SET requester_id_uuid = u.auth_user_id
    FROM public.users u
    WHERE tr.requester_id = u.id
      AND tr.requester_id_uuid IS NULL;

    ALTER TABLE public.transaction_requests DROP CONSTRAINT IF EXISTS transaction_requests_requester_id_fkey;
    ALTER TABLE public.transaction_requests ALTER COLUMN requester_id_uuid SET NOT NULL;
    ALTER TABLE public.transaction_requests DROP COLUMN requester_id;
    ALTER TABLE public.transaction_requests RENAME COLUMN requester_id_uuid TO requester_id;
  END IF;
END $$;

-- chats.user1_id / chats.user2_id
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'chats'
      AND column_name = 'user1_id'
      AND data_type IN ('integer', 'bigint', 'smallint')
  ) THEN
    ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS user1_id_uuid uuid;

    UPDATE public.chats c
    SET user1_id_uuid = u.auth_user_id
    FROM public.users u
    WHERE c.user1_id = u.id
      AND c.user1_id_uuid IS NULL;

    ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_user1_id_fkey;
    ALTER TABLE public.chats ALTER COLUMN user1_id_uuid SET NOT NULL;
    ALTER TABLE public.chats DROP COLUMN user1_id;
    ALTER TABLE public.chats RENAME COLUMN user1_id_uuid TO user1_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'chats'
      AND column_name = 'user2_id'
      AND data_type IN ('integer', 'bigint', 'smallint')
  ) THEN
    ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS user2_id_uuid uuid;

    UPDATE public.chats c
    SET user2_id_uuid = u.auth_user_id
    FROM public.users u
    WHERE c.user2_id = u.id
      AND c.user2_id_uuid IS NULL;

    ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_user2_id_fkey;
    ALTER TABLE public.chats ALTER COLUMN user2_id_uuid SET NOT NULL;
    ALTER TABLE public.chats DROP COLUMN user2_id;
    ALTER TABLE public.chats RENAME COLUMN user2_id_uuid TO user2_id;
  END IF;
END $$;

-- messages.sender_id / messages.deleted_by (if present)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'messages'
      AND column_name = 'sender_id'
      AND data_type IN ('integer', 'bigint', 'smallint')
  ) THEN
    ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_id_uuid uuid;

    UPDATE public.messages m
    SET sender_id_uuid = u.auth_user_id
    FROM public.users u
    WHERE m.sender_id = u.id
      AND m.sender_id_uuid IS NULL;

    ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
    ALTER TABLE public.messages ALTER COLUMN sender_id_uuid SET NOT NULL;
    ALTER TABLE public.messages DROP COLUMN sender_id;
    ALTER TABLE public.messages RENAME COLUMN sender_id_uuid TO sender_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'messages'
      AND column_name = 'deleted_by'
      AND data_type IN ('integer', 'bigint', 'smallint')
  ) THEN
    ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS deleted_by_uuid uuid;

    UPDATE public.messages m
    SET deleted_by_uuid = u.auth_user_id
    FROM public.users u
    WHERE m.deleted_by = u.id
      AND m.deleted_by_uuid IS NULL;

    ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_deleted_by_fkey;
    ALTER TABLE public.messages DROP COLUMN deleted_by;
    ALTER TABLE public.messages RENAME COLUMN deleted_by_uuid TO deleted_by;
  END IF;
END $$;

-- chat_pinned_messages.pinned_by (if table/column exist)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'chat_pinned_messages'
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'chat_pinned_messages'
        AND column_name = 'pinned_by'
        AND data_type IN ('integer', 'bigint', 'smallint')
    ) THEN
      ALTER TABLE public.chat_pinned_messages ADD COLUMN IF NOT EXISTS pinned_by_uuid uuid;

      UPDATE public.chat_pinned_messages p
      SET pinned_by_uuid = u.auth_user_id
      FROM public.users u
      WHERE p.pinned_by = u.id
        AND p.pinned_by_uuid IS NULL;

      ALTER TABLE public.chat_pinned_messages DROP CONSTRAINT IF EXISTS chat_pinned_messages_pinned_by_fkey;
      ALTER TABLE public.chat_pinned_messages DROP COLUMN pinned_by;
      ALTER TABLE public.chat_pinned_messages RENAME COLUMN pinned_by_uuid TO pinned_by;
    END IF;
  END IF;
END $$;

-- favourites.user_id (if table/column exist)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'favourites'
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'favourites'
        AND column_name = 'user_id'
        AND data_type IN ('integer', 'bigint', 'smallint')
    ) THEN
      ALTER TABLE public.favourites ADD COLUMN IF NOT EXISTS user_id_uuid uuid;

      UPDATE public.favourites f
      SET user_id_uuid = u.auth_user_id
      FROM public.users u
      WHERE f.user_id = u.id
        AND f.user_id_uuid IS NULL;

      ALTER TABLE public.favourites DROP CONSTRAINT IF EXISTS favourites_user_id_fkey;
      ALTER TABLE public.favourites ALTER COLUMN user_id_uuid SET NOT NULL;
      ALTER TABLE public.favourites DROP COLUMN user_id;
      ALTER TABLE public.favourites RENAME COLUMN user_id_uuid TO user_id;
    END IF;
  END IF;
END $$;

-- 2) Swap users primary key from integer id -> uuid (derived from auth_user_id), then drop auth_user_id.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'id'
      AND data_type IN ('integer', 'bigint', 'smallint')
  )
  AND EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'auth_user_id'
  ) THEN
    ALTER TABLE public.users ADD COLUMN IF NOT EXISTS id_uuid uuid;

    UPDATE public.users
    SET id_uuid = auth_user_id
    WHERE id_uuid IS NULL;

    ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_auth_user_id_fkey;
    ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_auth_user_id_key;
    ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_pkey;

    ALTER TABLE public.users ALTER COLUMN id_uuid SET NOT NULL;

    ALTER TABLE public.users DROP COLUMN id;
    ALTER TABLE public.users RENAME COLUMN id_uuid TO id;

    ALTER TABLE public.users ADD CONSTRAINT users_pkey PRIMARY KEY (id);
    ALTER TABLE public.users
      ADD CONSTRAINT users_id_fkey
      FOREIGN KEY (id)
      REFERENCES auth.users (id)
      ON DELETE CASCADE;

    ALTER TABLE public.users DROP COLUMN auth_user_id;
  END IF;
END $$;

-- 3) Recreate all user foreign keys against public.users(id uuid).

ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS items_owner_id_fkey,
  ADD CONSTRAINT items_owner_id_fkey
    FOREIGN KEY (owner_id) REFERENCES public.users (id) ON DELETE CASCADE;

ALTER TABLE public.transaction_requests
  DROP CONSTRAINT IF EXISTS transaction_requests_requester_id_fkey,
  ADD CONSTRAINT transaction_requests_requester_id_fkey
    FOREIGN KEY (requester_id) REFERENCES public.users (id) ON DELETE CASCADE;

ALTER TABLE public.chats
  DROP CONSTRAINT IF EXISTS chats_user1_id_fkey,
  DROP CONSTRAINT IF EXISTS chats_user2_id_fkey,
  ADD CONSTRAINT chats_user1_id_fkey
    FOREIGN KEY (user1_id) REFERENCES public.users (id) ON DELETE CASCADE,
  ADD CONSTRAINT chats_user2_id_fkey
    FOREIGN KEY (user2_id) REFERENCES public.users (id) ON DELETE CASCADE;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_sender_id_fkey,
  ADD CONSTRAINT messages_sender_id_fkey
    FOREIGN KEY (sender_id) REFERENCES public.users (id) ON DELETE CASCADE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'deleted_by'
  ) THEN
    ALTER TABLE public.messages
      DROP CONSTRAINT IF EXISTS messages_deleted_by_fkey,
      ADD CONSTRAINT messages_deleted_by_fkey
        FOREIGN KEY (deleted_by) REFERENCES public.users (id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'chat_pinned_messages'
  ) AND EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'chat_pinned_messages' AND column_name = 'pinned_by'
  ) THEN
    ALTER TABLE public.chat_pinned_messages
      DROP CONSTRAINT IF EXISTS chat_pinned_messages_pinned_by_fkey,
      ADD CONSTRAINT chat_pinned_messages_pinned_by_fkey
        FOREIGN KEY (pinned_by) REFERENCES public.users (id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'favourites'
  ) AND EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'favourites' AND column_name = 'user_id'
  ) THEN
    ALTER TABLE public.favourites
      DROP CONSTRAINT IF EXISTS favourites_user_id_fkey,
      ADD CONSTRAINT favourites_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE;
  END IF;
END $$;

DROP INDEX IF EXISTS public.chats_user_pair_unique_idx;
CREATE UNIQUE INDEX IF NOT EXISTS chats_user_pair_unique_idx
ON public.chats (LEAST(user1_id, user2_id), GREATEST(user1_id, user2_id));

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_select_self ON public.users;
CREATE POLICY users_select_self
ON public.users
FOR SELECT
TO authenticated
USING (auth.uid() = id);

DROP POLICY IF EXISTS users_upsert_self ON public.users;
CREATE POLICY users_upsert_self
ON public.users
FOR ALL
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS items_select_all ON public.items;
CREATE POLICY items_select_all
ON public.items
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS items_owner_write ON public.items;
CREATE POLICY items_owner_write
ON public.items
FOR ALL
TO authenticated
USING (auth.uid() = owner_id)
WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS transaction_requests_access_participants ON public.transaction_requests;
CREATE POLICY transaction_requests_access_participants
ON public.transaction_requests
FOR SELECT
TO authenticated
USING (
  auth.uid() = requester_id OR
  EXISTS (
    SELECT 1
    FROM public.items i
    WHERE i.id = item_id AND i.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS transaction_requests_create_requester ON public.transaction_requests;
CREATE POLICY transaction_requests_create_requester
ON public.transaction_requests
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = requester_id);

DROP POLICY IF EXISTS transaction_requests_update_owner_or_requester ON public.transaction_requests;
CREATE POLICY transaction_requests_update_owner_or_requester
ON public.transaction_requests
FOR UPDATE
TO authenticated
USING (
  auth.uid() = requester_id OR
  EXISTS (
    SELECT 1
    FROM public.items i
    WHERE i.id = item_id AND i.owner_id = auth.uid()
  )
)
WITH CHECK (
  auth.uid() = requester_id OR
  EXISTS (
    SELECT 1
    FROM public.items i
    WHERE i.id = item_id AND i.owner_id = auth.uid()
  )
);

-- 4) Re-enable strict RLS and remove anonymous test access for chat-related tables.
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_message_pins ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'chat_pinned_messages'
  ) THEN
    ALTER TABLE public.chat_pinned_messages ENABLE ROW LEVEL SECURITY;
  END IF;
END $$;

REVOKE ALL ON TABLE public.chats FROM anon;
REVOKE ALL ON TABLE public.messages FROM anon;
REVOKE ALL ON TABLE public.ai_messages FROM anon;
REVOKE ALL ON TABLE public.ai_message_pins FROM anon;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'chat_pinned_messages'
  ) THEN
    EXECUTE 'REVOKE ALL ON TABLE public.chat_pinned_messages FROM anon';
  END IF;
END $$;

DROP POLICY IF EXISTS "Anon test read ai pins" ON public.ai_message_pins;
DROP POLICY IF EXISTS "Anon test write ai pins" ON public.ai_message_pins;
DROP POLICY IF EXISTS "Anon test update ai pins" ON public.ai_message_pins;
DROP POLICY IF EXISTS "Anon test delete ai pins" ON public.ai_message_pins;

DROP POLICY IF EXISTS chats_select_participants ON public.chats;
CREATE POLICY chats_select_participants
ON public.chats
FOR SELECT
TO authenticated
USING (auth.uid() = user1_id OR auth.uid() = user2_id);

DROP POLICY IF EXISTS chats_insert_participants ON public.chats;
CREATE POLICY chats_insert_participants
ON public.chats
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user1_id OR auth.uid() = user2_id);

DROP POLICY IF EXISTS chats_update_participants ON public.chats;
CREATE POLICY chats_update_participants
ON public.chats
FOR UPDATE
TO authenticated
USING (auth.uid() = user1_id OR auth.uid() = user2_id)
WITH CHECK (auth.uid() = user1_id OR auth.uid() = user2_id);

DROP POLICY IF EXISTS messages_select_participants ON public.messages;
CREATE POLICY messages_select_participants
ON public.messages
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = chat_id
      AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
  )
);

DROP POLICY IF EXISTS messages_insert_sender_participant ON public.messages;
CREATE POLICY messages_insert_sender_participant
ON public.messages
FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = chat_id
      AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
  )
);

DROP POLICY IF EXISTS messages_update_participant ON public.messages;
CREATE POLICY messages_update_participant
ON public.messages
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = chat_id
      AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = chat_id
      AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
  )
);

DROP POLICY IF EXISTS "Users can view their own AI messages" ON public.ai_messages;
CREATE POLICY "Users can view their own AI messages"
ON public.ai_messages
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own AI messages" ON public.ai_messages;
CREATE POLICY "Users can insert their own AI messages"
ON public.ai_messages
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own AI pins" ON public.ai_message_pins;
CREATE POLICY "Users can view their own AI pins"
ON public.ai_message_pins
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can pin their own AI messages" ON public.ai_message_pins;
CREATE POLICY "Users can pin their own AI messages"
ON public.ai_message_pins
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1
    FROM public.ai_messages m
    WHERE m.id = message_id
      AND m.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Users can unpin their own AI messages" ON public.ai_message_pins;
CREATE POLICY "Users can unpin their own AI messages"
ON public.ai_message_pins
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'chat_pinned_messages'
  ) THEN
    EXECUTE 'DROP POLICY IF EXISTS chat_pinned_messages_select_participants ON public.chat_pinned_messages';
    EXECUTE '
      CREATE POLICY chat_pinned_messages_select_participants
      ON public.chat_pinned_messages
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.chats c
          WHERE c.id = chat_id
            AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
        )
      )';

    EXECUTE 'DROP POLICY IF EXISTS chat_pinned_messages_insert_participants ON public.chat_pinned_messages';
    EXECUTE '
      CREATE POLICY chat_pinned_messages_insert_participants
      ON public.chat_pinned_messages
      FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.chats c
          WHERE c.id = chat_id
            AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
        )
      )';

    EXECUTE 'DROP POLICY IF EXISTS chat_pinned_messages_delete_participants ON public.chat_pinned_messages';
    EXECUTE '
      CREATE POLICY chat_pinned_messages_delete_participants
      ON public.chat_pinned_messages
      FOR DELETE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.chats c
          WHERE c.id = chat_id
            AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
        )
      )';
  END IF;
END $$;

-- 5) Recreate chat RPC functions with UUID actor IDs.

CREATE TABLE IF NOT EXISTS public.chat_pinned_messages (
  chat_id integer NOT NULL REFERENCES public.chats (id) ON DELETE CASCADE,
  message_id integer NOT NULL REFERENCES public.messages (id) ON DELETE CASCADE,
  pinned_at timestamptz NOT NULL DEFAULT now(),
  pinned_by uuid REFERENCES public.users (id) ON DELETE SET NULL,
  PRIMARY KEY (chat_id, message_id)
);

CREATE OR REPLACE FUNCTION public.pin_message_as_user(
  p_chat_id integer,
  p_message_id integer,
  p_actor_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'actor_id is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chats c
    JOIN public.messages m ON m.id = p_message_id AND m.chat_id = c.id
    WHERE c.id = p_chat_id
      AND (c.user1_id = p_actor_id OR c.user2_id = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not allowed to pin this message';
  END IF;

  INSERT INTO public.chat_pinned_messages (chat_id, message_id, pinned_by)
  VALUES (p_chat_id, p_message_id, p_actor_id)
  ON CONFLICT (chat_id, message_id)
  DO UPDATE SET pinned_at = now(), pinned_by = excluded.pinned_by;

  UPDATE public.chats
  SET
    pinned_message_id = p_message_id,
    pinned_at = now()
  WHERE id = p_chat_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.unpin_message_as_user(
  p_chat_id integer,
  p_message_id integer,
  p_actor_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'actor_id is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = p_chat_id
      AND (c.user1_id = p_actor_id OR c.user2_id = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not allowed to unpin in this chat';
  END IF;

  DELETE FROM public.chat_pinned_messages
  WHERE chat_id = p_chat_id AND message_id = p_message_id;

  UPDATE public.chats
  SET
    pinned_message_id = (
      SELECT p.message_id
      FROM public.chat_pinned_messages p
      WHERE p.chat_id = p_chat_id
      ORDER BY p.pinned_at DESC
      LIMIT 1
    ),
    pinned_at = (
      SELECT p.pinned_at
      FROM public.chat_pinned_messages p
      WHERE p.chat_id = p_chat_id
      ORDER BY p.pinned_at DESC
      LIMIT 1
    )
  WHERE id = p_chat_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_pinned_messages_as_user(
  p_chat_id integer,
  p_actor_id uuid
)
RETURNS SETOF public.chat_pinned_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'actor_id is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = p_chat_id
      AND (c.user1_id = p_actor_id OR c.user2_id = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not allowed to view pins in this chat';
  END IF;

  RETURN QUERY
  SELECT p.*
  FROM public.chat_pinned_messages p
  WHERE p.chat_id = p_chat_id
  ORDER BY p.pinned_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_chat_as_read_as_user(
  p_chat_id integer,
  p_actor_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'actor_id is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chats c
    WHERE c.id = p_chat_id
      AND (c.user1_id = p_actor_id OR c.user2_id = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not allowed to read this chat';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'read_at'
  ) THEN
    RETURN (
      WITH updated AS (
        UPDATE public.messages
        SET read_at = now()
        WHERE chat_id = p_chat_id
          AND sender_id <> p_actor_id
          AND read_at IS NULL
        RETURNING 1
      )
      SELECT count(*)::integer FROM updated
    );
  ELSE
    RETURN (
      WITH updated AS (
        UPDATE public.messages
        SET is_read = true
        WHERE chat_id = p_chat_id
          AND sender_id <> p_actor_id
          AND coalesce(is_read, false) = false
        RETURNING 1
      )
      SELECT count(*)::integer FROM updated
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.edit_message_as_user(
  p_message_id integer,
  p_actor_id uuid,
  p_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'actor_id is required';
  END IF;
  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RAISE EXCEPTION 'content is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.messages m
    JOIN public.chats c ON c.id = m.chat_id
    WHERE m.id = p_message_id
      AND m.sender_id = p_actor_id
      AND (c.user1_id = p_actor_id OR c.user2_id = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not allowed to edit this message';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'edited_at'
  ) THEN
    UPDATE public.messages
    SET content = btrim(p_content), edited_at = now()
    WHERE id = p_message_id;
  ELSE
    UPDATE public.messages
    SET content = btrim(p_content)
    WHERE id = p_message_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_message_as_user(
  p_message_id integer,
  p_actor_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'actor_id is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.messages m
    JOIN public.chats c ON c.id = m.chat_id
    WHERE m.id = p_message_id
      AND m.sender_id = p_actor_id
      AND (c.user1_id = p_actor_id OR c.user2_id = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not allowed to delete this message';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'deleted_at'
  ) THEN
    UPDATE public.messages
    SET
      content = '[deleted]',
      deleted_at = now(),
      deleted_by = p_actor_id
    WHERE id = p_message_id;
  ELSE
    DELETE FROM public.messages
    WHERE id = p_message_id;
  END IF;
END;
$$;

REVOKE ALL ON TABLE public.chat_pinned_messages FROM anon;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'pin_message_as_user'
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.pin_message_as_user(integer, integer, uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.unpin_message_as_user(integer, integer, uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.list_pinned_messages_as_user(integer, uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.mark_chat_as_read_as_user(integer, uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.edit_message_as_user(integer, uuid, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.delete_message_as_user(integer, uuid) FROM anon;

    GRANT EXECUTE ON FUNCTION public.pin_message_as_user(integer, integer, uuid) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.unpin_message_as_user(integer, integer, uuid) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.list_pinned_messages_as_user(integer, uuid) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.mark_chat_as_read_as_user(integer, uuid) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.edit_message_as_user(integer, uuid, text) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.delete_message_as_user(integer, uuid) TO authenticated;
  END IF;
END $$;

-- Keep realtime publication entry idempotent.
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ai_messages;
  EXCEPTION
    WHEN duplicate_object THEN
      NULL;
  END;
END $$;

commit;
