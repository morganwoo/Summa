# Summa social backend (Supabase)

The iOS app talks to Supabase directly: Supabase Auth for accounts, and PostgREST for data. There is no extra
server in between. Access is controlled in the database: every table has row level security, and anything about
another person goes through functions that check sign-in, friendship, blocks, privacy, and the friend limit.
The TypeScript API in `server/src` is unrelated; it only drafts plans.

## What you configure

Nothing secret goes into the app or into Git.

| Value (Supabase dashboard > Project Settings > API) | Where it goes | Secret? |
| --- | --- | --- |
| Project URL | `ios/Config/Secrets.xcconfig` as `SUPABASE_URL`, and `server/.env` | No |
| anon / publishable key | `ios/Config/Secrets.xcconfig` as `SUPABASE_ANON_KEY`, and `server/.env` | No (public by design) |
| service_role / secret key | `server/.env` only, as `SUPABASE_SERVICE_ROLE_KEY` | **Yes.** Never in `ios/`. Used only by `verify.mjs` on your machine. |
| Database password | Nowhere in this repo. Only if you apply the migration with `psql` or the Supabase CLI, typed at the prompt. | **Yes** |

Both `ios/Config/Secrets.xcconfig` and `server/.env` are git-ignored.

## Steps

1. **Apply the migration.** Dashboard > SQL Editor > New query, paste all of `migrations/0001_summa_social.sql`, Run.
   (Or `supabase db push`, or `psql "$DATABASE_URL" -f migrations/0001_summa_social.sql`.) It is safe to re-run.
2. **Auth.** Dashboard > Authentication > Providers > Email: enabled. For quick testing turn off "Confirm email";
   leave it on for real users (they confirm by email, then sign in).
3. **App.** Copy `ios/Config/Secrets.example.xcconfig` to `ios/Config/Secrets.xcconfig` and fill in the URL
   (written `https:/$()/your-ref.supabase.co`) and the anon key. Build and run; the Friends tab shows a sign-in form.
4. **Verify.** Copy `server/.env.example` to `server/.env`, fill in the three `SUPABASE_` values, then:

   ```sh
   cd server && node --env-file=.env supabase/verify.mjs
   ```

   It creates four throwaway accounts, signs them in, sets usernames, searches, sends and accepts a friend request,
   checks both sides see it, checks the two-friend free limit and that nobody can grant themselves Pro, then deletes
   the accounts. It prints one line per check and exits non-zero on the first failure.

## Summa Pro on the server

Unlimited friends needs the server to know an account is Pro. That comes from the `entitlements` table, which only
the `functions/sync-entitlement` edge function can write, after verifying an App Store transaction. Until that function
is deployed, the server treats every account as Free (two friends). Deploy notes are at the top of its `index.ts`.

## Tests without a Supabase project

- `test.sql`: access rules and friend limits on plain PostgreSQL (`createdb summa_test && psql -v ON_ERROR_STOP=1 -d summa_test -f test.sql`).
- `test-concurrency.sh`: simultaneous acceptances cannot exceed the limit.
