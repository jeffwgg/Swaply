# Supabase CLI Guideline

This guide is the command checklist for managing Swaply schema via Supabase CLI.

## 1. Install CLI

```bash
brew install supabase/tap/supabase
supabase --version
```

If Homebrew install fails due to Xcode/CommandLineTools:

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

If tools are outdated:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

## 2. Login

```bash
supabase login
```

## 3. Go to project root

```bash
cd /Users/jeffwg/Documents/Project/Swaply
```

## 4. Link your remote project

`project-ref` is the subdomain part of your URL:  
`https://rxcpoebnwtgpwfgkhloo.supabase.co` -> `rxcpoebnwtgpwfgkhloo`

```bash
supabase link --project-ref rxcpoebnwtgpwfgkhloo
```

## 5. Push schema migrations

Current migration file:
- `supabase/migrations/20260324131912_init_schema.sql`

Run:

```bash
supabase db push
```

## 6. Verify

Check in Supabase dashboard:
- `Table Editor`: `users`, `items`, `transaction_requests`, `chats`, `messages`
- `SQL Editor`: no failed migration

Optional local check:

```bash
supabase migration list
```

## 7. Future schema changes

Create a new migration each time you update schema:

```bash
supabase migration new <name>
```

Edit the generated SQL file, then push:

```bash
supabase db push
```

## Security reminders

- `project-ref` is not secret.
- `.env` should only contain `SUPABASE_URL` and `SUPABASE_ANON_KEY` for app runtime.
- Never put `service_role` key in Flutter code or `.env` used by mobile app.
