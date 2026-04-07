# Swaply

Hybrid marketplace Flutter app with Supabase backend.

## Supabase Setup

1. Create a Supabase project.
2. Open Supabase SQL Editor and run [`docs/supabase_schema.sql`](docs/supabase_schema.sql).
3. Update Supabase credentials in [lib/core/constants/app_config.dart](lib/core/constants/app_config.dart) with your Project URL and anon key.
4. Run the app:

```bash
flutter run
```

Important:
- The anon key is safe to commit (it's public by design).
- Security is enforced through Row Level Security (RLS) policies in your database.
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
