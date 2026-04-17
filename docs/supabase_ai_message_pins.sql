-- Persist AI message pins across app restarts/devices
-- Run this in Supabase SQL Editor

CREATE TABLE IF NOT EXISTS public.ai_message_pins (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message_id integer NOT NULL REFERENCES public.ai_messages(id) ON DELETE CASCADE,
  pinned_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  PRIMARY KEY (user_id, message_id)
);

ALTER TABLE public.ai_message_pins ENABLE ROW LEVEL SECURITY;

-- Users can only see their own AI pins
DROP POLICY IF EXISTS "Users can view their own AI pins" ON public.ai_message_pins;
CREATE POLICY "Users can view their own AI pins"
ON public.ai_message_pins
FOR SELECT
USING (auth.uid() = user_id);

-- Users can only create pins for their own messages
DROP POLICY IF EXISTS "Users can pin their own AI messages" ON public.ai_message_pins;
CREATE POLICY "Users can pin their own AI messages"
ON public.ai_message_pins
FOR INSERT
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1
    FROM public.ai_messages m
    WHERE m.id = message_id
      AND m.user_id = auth.uid()
  )
);

-- Users can only remove their own AI pins
DROP POLICY IF EXISTS "Users can unpin their own AI messages" ON public.ai_message_pins;
CREATE POLICY "Users can unpin their own AI messages"
ON public.ai_message_pins
FOR DELETE
USING (auth.uid() = user_id);

-- -------------------------------------------------------------
-- TESTING ONLY (NO LOGIN INTEGRATION YET)
-- Uncomment if you are still testing with anon + hardcoded user IDs.
-- Remove later using docs/auth_integration_todo.md instructions.
-- -------------------------------------------------------------
-- GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_message_pins TO anon;
-- DROP POLICY IF EXISTS "Anon test read ai pins" ON public.ai_message_pins;
-- CREATE POLICY "Anon test read ai pins"
-- ON public.ai_message_pins FOR SELECT USING (true);
-- DROP POLICY IF EXISTS "Anon test write ai pins" ON public.ai_message_pins;
-- CREATE POLICY "Anon test write ai pins"
-- ON public.ai_message_pins FOR INSERT WITH CHECK (true);
-- DROP POLICY IF EXISTS "Anon test update ai pins" ON public.ai_message_pins;
-- CREATE POLICY "Anon test update ai pins"
-- ON public.ai_message_pins FOR UPDATE USING (true) WITH CHECK (true);
-- DROP POLICY IF EXISTS "Anon test delete ai pins" ON public.ai_message_pins;
-- CREATE POLICY "Anon test delete ai pins"
-- ON public.ai_message_pins FOR DELETE USING (true);
