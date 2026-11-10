# Database migration guide

Migrations live in `taleemplus_backend/prisma/migrations/` and are applied with
`prisma migrate deploy` (never `db push` / `migrate reset` against shared data).

## Environments

| Environment | Database | How it is configured |
|---|---|---|
| Local development | Neon dev branch | `taleemplus_backend/.env` → `DATABASE_URL` |
| Production | Neon production database | Vercel project env (`vercel env pull` writes `.env.local`) |
| Automated tests | throwaway local PostgreSQL (e.g. `localhost:5434`) | `TEST_DATABASE_URL` |

**Nothing from this release has been applied to either Neon database.**

## Pending migration in this release

`20261109090000_files_assignments_location_bank` — purely additive:

| Change | Effect on existing rows |
|---|---|
| `academies` + `latitude`, `longitude`, `locationLabel`, `bankName`, `bankAccountNumber`, `bankIban`, `paymentInstructions` (all nullable) | none (NULL) |
| new tables `stored_files`, `assignments`, `assignment_submissions` (+ indexes, FKs) | none |

A documented manual rollback is in the same folder (`down.sql`). It deletes the
new tables' data — only use it after a backup.

## Procedure for production (requires your approval)

1. **Back up** (logical JSON export used by this project):
   ```powershell
   cd taleemplus_backend
   $env:DATABASE_URL = '<production URL from Vercel>'   # do not commit
   npm run db:backup
   ```
   Also create a Neon branch / point-in-time restore point in the Neon console.
2. **Check what will run** (read-only):
   ```powershell
   npx prisma migrate status
   ```
   Expect exactly one pending migration: `20261109090000_files_assignments_location_bank`.
3. **Apply**:
   ```powershell
   npx prisma migrate deploy
   ```
4. **Verify**:
   ```powershell
   npx prisma migrate status          # "Database schema is up to date"
   curl https://taleemplus.vercel.app/health
   ```
5. Deploy the backend code (see `VERCEL_DEPLOYMENT_GUIDE.md`). The GitHub
   `vercel.yml` workflow runs `prisma migrate deploy` before deploying when its
   secrets are configured, so steps 3–4 can also happen there.

Order matters: **migrate first, then deploy code**. Old code ignores the new
columns/tables, so a migrated database is safe for the currently deployed
version.

## Creating new migrations (developers)

```powershell
# against a scratch database, never Neon production
$env:DATABASE_URL = 'postgresql://postgres@localhost:5434/taleemplus_test?schema=public'
npx prisma migrate deploy                       # bring scratch DB up to date
# edit prisma/schema.prisma, then generate the SQL by diffing:
npx prisma migrate diff --from-url $env:DATABASE_URL --to-schema-datamodel prisma/schema.prisma --script > prisma/migrations/<timestamp>_<name>/migration.sql
npx prisma migrate deploy && npx prisma generate
```

Review the SQL: prefer additive changes (new nullable columns, new tables);
split renames/drops into expand → migrate data → contract steps.

## Local throwaway database for tests

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\initdb.exe' -D <dir> -U postgres --auth=trust -E UTF8
& 'C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe' -D <dir> -o "-p 5434" start
& 'C:\Program Files\PostgreSQL\18\bin\createdb.exe' -h localhost -p 5434 -U postgres taleemplus_test
```

Note: the repository's `taleemplus_backend/.pgdata` folder is **not** a valid
cluster (`npm run db:start` fails); use a fresh directory as above.
