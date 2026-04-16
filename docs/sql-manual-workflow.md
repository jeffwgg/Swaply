# SQL Change Workflow (Manual)

## Team Agreement

Starting now, database changes follow this process:

1. Copilot provides SQL scripts in chat.
2. You manually run the SQL in Supabase SQL Editor.
3. Copilot does not create migration files unless you explicitly request migration files.

## Why We Use This

1. Better visibility of every DB change.
2. Easier learning and understanding of SQL logic.
3. More control when debugging RLS and permissions.

## Standard Delivery Format for Future SQL

When requesting DB changes, Copilot should provide:

1. Pre-check queries (optional but recommended).
2. Main SQL script.
3. Grant/policy updates if needed.
4. Verification queries.
5. Optional rollback SQL.

## Execution Checklist

1. Run SQL in Supabase SQL Editor (dev/staging first when possible).
2. Confirm script success (no SQL errors).
3. Run verification queries.
4. Test one success path and one unauthorized path.
5. Record date + purpose of change in project notes.
