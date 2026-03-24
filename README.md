# Swaply

Hybrid marketplace Flutter app with Supabase backend.

## Supabase Setup

1. Create a Supabase project.
2. Open Supabase SQL Editor and run [`docs/supabase_schema.sql`](docs/supabase_schema.sql).
3. Get your Project URL and anon key from Supabase project settings.
4. Create a local `.env` file (this file is already gitignored):

```bash
cp .env.example .env
```

5. Put your credentials in `.env`:

```bash
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

6. Run the app using that env file:

```bash
flutter run --dart-define-from-file=.env
```

If you do not provide these values, the app still starts, but Supabase calls will be unavailable.

Important:
- Use only the anon key in the app.
- Never put `service_role` key in Flutter/mobile code.

## Schema via CLI

Migration file is prepared at:
- `supabase/migrations/20260324131912_init_schema.sql`
- Full command guideline: [`docs/supabase-cli-guide.md`](docs/supabase-cli-guide.md)

Run this to apply with Supabase CLI:

```bash
# one-time
supabase login

# from project root
cd /Users/jeffwg/Documents/Project/Swaply

# one-time (if not linked yet)
supabase link --project-ref YOUR_PROJECT_REF

# push all local migrations to remote database
supabase db push
```

## Notes

- Supabase initialization happens in [main.dart](lib/main.dart).
- Supabase client access is centralized in [lib/services/supabase_service.dart](lib/services/supabase_service.dart).
- Starter repositories are available in `lib/repositories` and map directly to your schema tables.
