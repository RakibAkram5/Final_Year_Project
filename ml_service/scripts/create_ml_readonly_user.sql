-- =============================================================================
-- TaleemPlus ML — dedicated READ-ONLY PostgreSQL role
-- =============================================================================
-- Creates `taleemplus_ml_reader`, a least-privilege role the ML service uses to
-- READ academy data. It can run SELECT on exactly the six tables the extractor
-- needs and nothing else. It CANNOT INSERT/UPDATE/DELETE/TRUNCATE/CREATE/ALTER/
-- DROP, and it is not a superuser.
--
-- Database provider: Neon PostgreSQL (serverless).  Migration owner: neondb_owner.
--
-- HOW TO RUN (choose one) — run as the database owner `neondb_owner`:
--
--   A) Neon SQL Editor (easiest, free):
--      Neon Console -> your project -> "SQL Editor". Paste this file, but first
--      replace  :'ml_password'  with a real strong password in single quotes,
--      e.g.  PASSWORD 'PASTE_A_STRONG_PASSWORD_HERE'.  Do NOT commit that edit.
--
--   B) psql against the DIRECT (non-pooler) endpoint — note: remove "-pooler"
--      from the host. Pass the password as a variable (RAW, with no surrounding
--      single quotes — the :'ml_password' syntax below adds the SQL quotes for
--      you). Keeping it in a variable avoids writing it into this file:
--
--        psql "postgresql://neondb_owner:<owner-pwd>@<your-neon-host>.<region>.aws.neon.tech/neondb?sslmode=require" \
--             -v ml_password="CHOOSE_A_STRONG_PASSWORD" \
--             -f ml_service/scripts/create_ml_readonly_user.sql
--
-- SECURITY NOTES:
--   * No password is stored in this file. :'ml_password' is a psql variable.
--   * Run privileged DDL only with the project owner's approval.
--   * After running, put the ml_reader connection string in ml_service/.env
--     (git-ignored) only — never in .env.example and never committed.
-- =============================================================================

-- 1) Create the login role. (Fails loudly if it already exists; that's fine —
--    comment this block out and jump to the GRANTs to re-apply privileges.)
CREATE ROLE taleemplus_ml_reader LOGIN PASSWORD :'ml_password';

-- 2) Defense in depth: force every session this role opens to be read-only,
--    so even an accidental write is rejected by the server before execution.
ALTER ROLE taleemplus_ml_reader SET default_transaction_read_only = on;

-- Optional guard rails (safe to keep):
ALTER ROLE taleemplus_ml_reader CONNECTION LIMIT 5;
ALTER ROLE taleemplus_ml_reader SET statement_timeout = '30s';

-- 3) Connect + schema usage only (no object creation).
GRANT CONNECT ON DATABASE neondb TO taleemplus_ml_reader;
GRANT USAGE  ON SCHEMA   public  TO taleemplus_ml_reader;
REVOKE CREATE ON SCHEMA   public  FROM taleemplus_ml_reader;  -- cannot make objects

-- 4) SELECT on EXACTLY the six tables the ML extractor reads. Nothing else.
GRANT SELECT ON TABLE
    public.academies,
    public.users,
    public.fee_challans,
    public.attendance_records,
    public.test_marks,
    public.quizzes
TO taleemplus_ml_reader;

-- 5) Future tables created by the real migration owner (neondb_owner) will also
--    be readable without re-running grants. This covers `prisma migrate deploy`.
--    (Scoped to the owner role, so only owner-created tables are auto-granted.)
ALTER DEFAULT PRIVILEGES FOR ROLE neondb_owner IN SCHEMA public
    GRANT SELECT ON TABLES TO taleemplus_ml_reader;

-- -----------------------------------------------------------------------------
-- VERIFICATION (read-only; safe to run as neondb_owner after the grants above)
-- -----------------------------------------------------------------------------
-- a) The role must NOT have any write privilege on the six tables:
--    (expected: zero rows)
-- SELECT grantee, table_name, privilege_type
--   FROM information_schema.role_table_grants
--  WHERE grantee = 'taleemplus_ml_reader'
--    AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER');
--
-- b) The role MUST have SELECT on the six tables (expected: six rows):
-- SELECT table_name, privilege_type
--   FROM information_schema.role_table_grants
--  WHERE grantee = 'taleemplus_ml_reader' AND privilege_type = 'SELECT'
--  ORDER BY table_name;
--
-- c) Not a superuser / no create-role / no create-db (expected: all false):
-- SELECT rolsuper, rolcreaterole, rolcreatedb, rolbypassrls
--   FROM pg_roles WHERE rolname = 'taleemplus_ml_reader';
--
-- d) Row-Level Security: this project does NOT use RLS. Tenant (academy)
--    isolation is enforced in application/extractor queries that always filter
--    `academyId = $1`. A DB read-only role can therefore read all academies'
--    rows at the DB layer. If you later want DB-enforced isolation, add RLS
--    policies keyed on a session variable — but that is a separate change and is
--    not required for the current architecture.
-- =============================================================================
