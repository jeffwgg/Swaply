


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."chats" (
    "id" integer NOT NULL,
    "item_id" integer NOT NULL,
    "last_message" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pinned_message_id" bigint,
    "pinned_at" timestamp with time zone,
    "user1_id" "uuid" NOT NULL,
    "user2_id" "uuid" NOT NULL
);


ALTER TABLE "public"."chats" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_or_get_item_chat"("p_user_a" "uuid", "p_user_b" "uuid", "p_item_id" "uuid") RETURNS "public"."chats"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."create_or_get_item_chat"("p_user_a" "uuid", "p_user_b" "uuid", "p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_id"() RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  select u.id
  from public.users u
  where u.auth_user_id = auth.uid()
  limit 1;
$$;


ALTER FUNCTION "public"."current_user_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_message_as_user"("p_message_id" integer, "p_actor_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."delete_message_as_user"("p_message_id" integer, "p_actor_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."edit_message_as_user"("p_message_id" integer, "p_actor_id" "uuid", "p_content" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."edit_message_as_user"("p_message_id" integer, "p_actor_id" "uuid", "p_content" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_ai_conversation_for_user"("p_user_id" "uuid", "p_welcome_message" "text" DEFAULT 'Hi! I''m Swaply Buddy. I can help you with listings, trades, requests, and chat tips anytime.'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_message_id integer;
begin
  if p_user_id is null then
    raise exception 'user_id is required';
  end if;

  if exists (
    select 1
    from public.ai_messages m
    where m.user_id = p_user_id
    limit 1
  ) then
    return;
  end if;

  insert into public.ai_messages (user_id, content, is_ai)
  values (p_user_id, btrim(coalesce(p_welcome_message, '')), true)
  returning id into v_message_id;

  insert into public.ai_message_pins (user_id, message_id)
  values (p_user_id, v_message_id)
  on conflict (user_id, message_id) do nothing;
end;
$$;


ALTER FUNCTION "public"."ensure_ai_conversation_for_user"("p_user_id" "uuid", "p_welcome_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_chat_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_chat_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_message_insert_update_chat"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  update public.chats
  set
    last_message = new.content,
    updated_at = now()
  where id = new.chat_id;

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_message_insert_update_chat"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_users_ai_conversation_init"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform public.ensure_ai_conversation_for_user(new.id);
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_users_ai_conversation_init"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_pinned_messages" (
    "chat_id" integer NOT NULL,
    "message_id" integer NOT NULL,
    "pinned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pinned_by" "uuid"
);

ALTER TABLE ONLY "public"."chat_pinned_messages" REPLICA IDENTITY FULL;


ALTER TABLE "public"."chat_pinned_messages" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_pinned_messages_as_user"("p_chat_id" integer, "p_actor_id" "uuid") RETURNS SETOF "public"."chat_pinned_messages"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."list_pinned_messages_as_user"("p_chat_id" integer, "p_actor_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_chat_as_read_as_user"("p_chat_id" integer, "p_actor_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."mark_chat_as_read_as_user"("p_chat_id" integer, "p_actor_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notifications_set_read_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.is_read and (old.is_read is distinct from true) and new.read_at is null then
    new.read_at := now();
  elsif not new.is_read then
    new.read_at := null;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."notifications_set_read_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pin_message_as_user"("p_chat_id" integer, "p_message_id" integer, "p_actor_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."pin_message_as_user"("p_chat_id" integer, "p_message_id" integer, "p_actor_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."items" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "price" numeric(12,2),
    "listing_type" "text" NOT NULL,
    "status" "text" DEFAULT 'available'::"text" NOT NULL,
    "category" "text" NOT NULL,
    "image_urls" "text"[],
    "preference" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "replied_to" integer,
    "address" "text",
    "latitude" double precision,
    "longitude" double precision,
    "owner_id" "uuid" NOT NULL,
    CONSTRAINT "items_listing_type_check" CHECK (("listing_type" = ANY (ARRAY['sell'::"text", 'trade'::"text", 'both'::"text"]))),
    CONSTRAINT "items_status_check" CHECK (("status" = ANY (ARRAY['available'::"text", 'pending'::"text", 'reserved'::"text", 'accepted'::"text", 'completed'::"text", 'rejected'::"text", 'dropped'::"text", 'confirmed'::"text"])))
);


ALTER TABLE "public"."items" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_items"("query" "text") RETURNS SETOF "public"."items"
    LANGUAGE "sql"
    AS $$
  select items.*
  from items
  join users on users.id = items.owner_id
  where items.name ilike '%' || query || '%'
     or users.username ilike '%' || query || '%';
$$;


ALTER FUNCTION "public"."search_items"("query" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unpin_message_as_user"("p_chat_id" integer, "p_message_id" integer, "p_actor_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."unpin_message_as_user"("p_chat_id" integer, "p_message_id" integer, "p_actor_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_message_pins" (
    "user_id" "uuid" NOT NULL,
    "message_id" integer NOT NULL,
    "pinned_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."ai_message_pins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_messages" (
    "id" integer NOT NULL,
    "user_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "is_ai" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."ai_messages" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."ai_messages_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."ai_messages_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ai_messages_id_seq" OWNED BY "public"."ai_messages"."id";



ALTER TABLE "public"."chats" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."chats_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."favourites" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "item_id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."favourites" OWNER TO "postgres";


ALTER TABLE "public"."favourites" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."favourites_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."follows" (
    "follower_id" "uuid" NOT NULL,
    "followee_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."follows" REPLICA IDENTITY FULL;


ALTER TABLE "public"."follows" OWNER TO "postgres";


ALTER TABLE "public"."items" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" integer NOT NULL,
    "chat_id" integer NOT NULL,
    "content" "text" NOT NULL,
    "is_read" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sender_id" "uuid" NOT NULL
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


ALTER TABLE "public"."messages" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."messages_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "actor_id" "uuid",
    "type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_read" boolean DEFAULT false NOT NULL,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notifications_type_check" CHECK (("type" = ANY (ARRAY['chat'::"text", 'trade'::"text", 'general'::"text", 'follow'::"text", 'transaction'::"text"])))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payments" (
    "payment_id" integer NOT NULL,
    "payment_intent_id" "text" NOT NULL,
    "payment_method" "text" NOT NULL,
    "payment_amount" numeric NOT NULL,
    "payment_status" "text" NOT NULL,
    "transaction_id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."payments" OWNER TO "postgres";


ALTER TABLE "public"."payments" ALTER COLUMN "payment_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."payments_payment_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."transactions" (
    "transaction_id" integer NOT NULL,
    "buyer_id" "uuid" NOT NULL,
    "seller_id" "uuid" NOT NULL,
    "item_id" integer NOT NULL,
    "traded_item_id" integer,
    "transaction_type" "text",
    "transaction_status" "text" DEFAULT '''pending''::text'::"text",
    "item_price" numeric,
    "shipping_fee" numeric,
    "total_amount" numeric,
    "fulfillment_method" "text",
    "address" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cancelled_by" "text"
);


ALTER TABLE "public"."transactions" OWNER TO "postgres";


ALTER TABLE "public"."transactions" ALTER COLUMN "transaction_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."transaction_transaction_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."user_chat_pins" (
    "user_id" "uuid" NOT NULL,
    "chat_id" integer NOT NULL,
    "pinned_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_chat_pins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "username" "text" NOT NULL,
    "email" "text" NOT NULL,
    "profile_image" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "full_name" "text",
    "bio" "text",
    "phone" "text",
    "gender" "text",
    "birthdate" "date",
    "rating" numeric DEFAULT 0.0,
    "total_reviews" integer DEFAULT 0,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "id" "uuid" NOT NULL
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."ai_messages" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ai_messages_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."ai_message_pins"
    ADD CONSTRAINT "ai_message_pins_pkey" PRIMARY KEY ("user_id", "message_id");



ALTER TABLE ONLY "public"."ai_messages"
    ADD CONSTRAINT "ai_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_pinned_messages"
    ADD CONSTRAINT "chat_pinned_messages_pkey" PRIMARY KEY ("chat_id", "message_id");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favourites"
    ADD CONSTRAINT "favourites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_pkey" PRIMARY KEY ("follower_id", "followee_id");



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_payment_intent_id_key" UNIQUE ("payment_intent_id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("payment_id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transaction_pkey" PRIMARY KEY ("transaction_id");



ALTER TABLE ONLY "public"."favourites"
    ADD CONSTRAINT "unique_favourite" UNIQUE ("user_id", "item_id");



ALTER TABLE ONLY "public"."user_chat_pins"
    ADD CONSTRAINT "user_chat_pins_pkey" PRIMARY KEY ("user_id", "chat_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "chats_user_pair_item_unique_idx" ON "public"."chats" USING "btree" (LEAST("user1_id", "user2_id"), GREATEST("user1_id", "user2_id"), "item_id");



CREATE INDEX "messages_chat_id_idx" ON "public"."messages" USING "btree" ("chat_id");



CREATE INDEX "notifications_recipient_created_idx" ON "public"."notifications" USING "btree" ("recipient_id", "created_at" DESC);



CREATE INDEX "notifications_recipient_unread_idx" ON "public"."notifications" USING "btree" ("recipient_id", "is_read", "created_at" DESC);



CREATE INDEX "user_chat_pins_user_pinned_at_idx" ON "public"."user_chat_pins" USING "btree" ("user_id", "pinned_at" DESC);



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."follows" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_chats_updated_at" BEFORE UPDATE ON "public"."chats" FOR EACH ROW EXECUTE FUNCTION "public"."handle_chat_updated_at"();



CREATE OR REPLACE TRIGGER "trg_messages_update_chat" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."handle_message_insert_update_chat"();



CREATE OR REPLACE TRIGGER "trg_notifications_set_read_at" BEFORE UPDATE ON "public"."notifications" FOR EACH ROW EXECUTE FUNCTION "public"."notifications_set_read_at"();



CREATE OR REPLACE TRIGGER "trg_users_init_ai_conversation" AFTER INSERT ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_users_ai_conversation_init"();



ALTER TABLE ONLY "public"."ai_message_pins"
    ADD CONSTRAINT "ai_message_pins_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."ai_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_message_pins"
    ADD CONSTRAINT "ai_message_pins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_messages"
    ADD CONSTRAINT "ai_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_pinned_messages"
    ADD CONSTRAINT "chat_pinned_messages_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_pinned_messages"
    ADD CONSTRAINT "chat_pinned_messages_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_pinned_messages"
    ADD CONSTRAINT "chat_pinned_messages_pinned_by_fkey" FOREIGN KEY ("pinned_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pinned_message_id_fkey" FOREIGN KEY ("pinned_message_id") REFERENCES "public"."messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_user1_id_fkey" FOREIGN KEY ("user1_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_user2_id_fkey" FOREIGN KEY ("user2_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favourites"
    ADD CONSTRAINT "fk_item" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favourites"
    ADD CONSTRAINT "fk_user" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_followee_id_fkey" FOREIGN KEY ("followee_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_transaction_id_fkey" FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("transaction_id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transaction_buyer_id_fkey1" FOREIGN KEY ("buyer_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transaction_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transaction_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transaction_traded_item_id_fkey" FOREIGN KEY ("traded_item_id") REFERENCES "public"."items"("id");



ALTER TABLE ONLY "public"."user_chat_pins"
    ADD CONSTRAINT "user_chat_pins_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_chat_pins"
    ADD CONSTRAINT "user_chat_pins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Allow all access for testing" ON "public"."items" USING (true) WITH CHECK (true);



CREATE POLICY "Allow individual users to insert their own profile" ON "public"."users" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Allow insert" ON "public"."items" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow read access" ON "public"."items" FOR SELECT USING (true);



CREATE POLICY "Anon test read realtime" ON "public"."ai_messages" FOR SELECT USING (true);



CREATE POLICY "Users can delete their own AI messages" ON "public"."ai_messages" FOR DELETE TO "authenticated" USING ((("auth"."uid"() = "user_id") AND ("is_ai" = false)));



CREATE POLICY "Users can insert their own AI messages" ON "public"."ai_messages" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can pin their own AI messages" ON "public"."ai_message_pins" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "user_id") AND (EXISTS ( SELECT 1
   FROM "public"."ai_messages" "m"
  WHERE (("m"."id" = "ai_message_pins"."message_id") AND ("m"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can unpin their own AI messages" ON "public"."ai_message_pins" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own profile" ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own AI messages" ON "public"."ai_messages" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "user_id") AND ("is_ai" = false))) WITH CHECK ((("auth"."uid"() = "user_id") AND ("is_ai" = false)));



CREATE POLICY "Users can view their own AI messages" ON "public"."ai_messages" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own AI pins" ON "public"."ai_message_pins" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."ai_message_pins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_pinned_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_pinned_messages_delete_participants" ON "public"."chat_pinned_messages" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "chat_pinned_messages"."chat_id") AND (("c"."user1_id" = "auth"."uid"()) OR ("c"."user2_id" = "auth"."uid"()))))));



CREATE POLICY "chat_pinned_messages_insert_participants" ON "public"."chat_pinned_messages" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "chat_pinned_messages"."chat_id") AND (("c"."user1_id" = "auth"."uid"()) OR ("c"."user2_id" = "auth"."uid"()))))));



CREATE POLICY "chat_pinned_messages_select_participants" ON "public"."chat_pinned_messages" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "chat_pinned_messages"."chat_id") AND (("c"."user1_id" = "auth"."uid"()) OR ("c"."user2_id" = "auth"."uid"()))))));



ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chats_insert_participants" ON "public"."chats" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id")));



CREATE POLICY "chats_select_participants" ON "public"."chats" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id")));



CREATE POLICY "chats_update_participants" ON "public"."chats" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id"))) WITH CHECK ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id")));



ALTER TABLE "public"."favourites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."follows" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "follows_delete_v1" ON "public"."follows" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "follower_id"));



CREATE POLICY "follows_insert_v1" ON "public"."follows" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "follower_id"));



CREATE POLICY "follows_select_v1" ON "public"."follows" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "items_owner_write" ON "public"."items" TO "authenticated" USING (("auth"."uid"() = "owner_id")) WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "items_select_all" ON "public"."items" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "messages_insert_sender_participant" ON "public"."messages" FOR INSERT TO "authenticated" WITH CHECK ((("sender_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "messages"."chat_id") AND (("c"."user1_id" = "auth"."uid"()) OR ("c"."user2_id" = "auth"."uid"())))))));



CREATE POLICY "messages_select_participants" ON "public"."messages" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "messages"."chat_id") AND (("c"."user1_id" = "auth"."uid"()) OR ("c"."user2_id" = "auth"."uid"()))))));



CREATE POLICY "messages_update_participant" ON "public"."messages" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "messages"."chat_id") AND (("c"."user1_id" = "auth"."uid"()) OR ("c"."user2_id" = "auth"."uid"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "messages"."chat_id") AND (("c"."user1_id" = "auth"."uid"()) OR ("c"."user2_id" = "auth"."uid"()))))));



ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notifications_delete_recipient" ON "public"."notifications" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "recipient_id"));



CREATE POLICY "notifications_insert_any_actor" ON "public"."notifications" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "actor_id"));



CREATE POLICY "notifications_insert_self" ON "public"."notifications" FOR INSERT TO "authenticated" WITH CHECK (((("actor_id" = "auth"."uid"()) AND ("recipient_id" IS NOT NULL)) OR (("actor_id" IS NULL) AND ("recipient_id" = "auth"."uid"()))));



CREATE POLICY "notifications_select_recipient" ON "public"."notifications" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "recipient_id"));



CREATE POLICY "notifications_update_recipient" ON "public"."notifications" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "recipient_id")) WITH CHECK (("auth"."uid"() = "recipient_id"));



ALTER TABLE "public"."payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payments_insert_buyer" ON "public"."payments" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."transactions" "t"
  WHERE (("t"."transaction_id" = "payments"."transaction_id") AND ("t"."buyer_id" = "auth"."uid"())))));



CREATE POLICY "payments_read_participants" ON "public"."payments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."transactions" "t"
  WHERE (("t"."transaction_id" = "payments"."transaction_id") AND (("t"."buyer_id" = "auth"."uid"()) OR ("t"."seller_id" = "auth"."uid"()))))));



CREATE POLICY "payments_update_buyer" ON "public"."payments" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."transactions" "t"
  WHERE (("t"."transaction_id" = "payments"."transaction_id") AND ("t"."buyer_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."transactions" "t"
  WHERE (("t"."transaction_id" = "payments"."transaction_id") AND ("t"."buyer_id" = "auth"."uid"())))));



ALTER TABLE "public"."transactions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "transactions_insert_participants" ON "public"."transactions" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "buyer_id") OR ("auth"."uid"() = "seller_id")));



CREATE POLICY "transactions_read_participants" ON "public"."transactions" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "buyer_id") OR ("auth"."uid"() = "seller_id")));



CREATE POLICY "transactions_update_participants" ON "public"."transactions" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "buyer_id") OR ("auth"."uid"() = "seller_id"))) WITH CHECK ((("auth"."uid"() = "buyer_id") OR ("auth"."uid"() = "seller_id")));



ALTER TABLE "public"."user_chat_pins" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_chat_pins_delete_self" ON "public"."user_chat_pins" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user_chat_pins_insert_self" ON "public"."user_chat_pins" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "user_chat_pins_select_self" ON "public"."user_chat_pins" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user_chat_pins_update_self" ON "public"."user_chat_pins" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_select_authenticated" ON "public"."users" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "users_upsert_self" ON "public"."users" TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."chats" TO "authenticated";



GRANT ALL ON FUNCTION "public"."create_or_get_item_chat"("p_user_a" "uuid", "p_user_b" "uuid", "p_item_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."delete_message_as_user"("p_message_id" integer, "p_actor_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."edit_message_as_user"("p_message_id" integer, "p_actor_id" "uuid", "p_content" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."ensure_ai_conversation_for_user"("p_user_id" "uuid", "p_welcome_message" "text") TO "authenticated";



GRANT SELECT,INSERT,DELETE ON TABLE "public"."chat_pinned_messages" TO "authenticated";



GRANT ALL ON FUNCTION "public"."list_pinned_messages_as_user"("p_chat_id" integer, "p_actor_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."mark_chat_as_read_as_user"("p_chat_id" integer, "p_actor_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."pin_message_as_user"("p_chat_id" integer, "p_message_id" integer, "p_actor_id" "uuid") TO "authenticated";



GRANT ALL ON TABLE "public"."items" TO "anon";
GRANT ALL ON TABLE "public"."items" TO "authenticated";



GRANT ALL ON FUNCTION "public"."unpin_message_as_user"("p_chat_id" integer, "p_message_id" integer, "p_actor_id" "uuid") TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ai_message_pins" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ai_messages" TO "authenticated";



GRANT SELECT,USAGE ON SEQUENCE "public"."ai_messages_id_seq" TO "authenticated";



GRANT USAGE ON SEQUENCE "public"."chats_id_seq" TO "anon";
GRANT SELECT,USAGE ON SEQUENCE "public"."chats_id_seq" TO "authenticated";



GRANT SELECT,INSERT,DELETE ON TABLE "public"."follows" TO "authenticated";
GRANT ALL ON TABLE "public"."follows" TO "dashboard_user";



GRANT USAGE ON SEQUENCE "public"."items_id_seq" TO "anon";
GRANT SELECT,USAGE ON SEQUENCE "public"."items_id_seq" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."messages" TO "authenticated";



GRANT USAGE ON SEQUENCE "public"."messages_id_seq" TO "anon";
GRANT SELECT,USAGE ON SEQUENCE "public"."messages_id_seq" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT,USAGE ON SEQUENCE "public"."payments_payment_id_seq" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."transactions" TO "authenticated";



GRANT SELECT,USAGE ON SEQUENCE "public"."transaction_transaction_id_seq" TO "authenticated";



GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT SELECT ON TABLE "public"."users" TO "anon";




