-- Additive only: no existing rows or columns are modified or removed.

-- Deactivated accounts keep all historical data (attendance, fees, marks)
-- but can no longer sign in or refresh tokens.
ALTER TYPE "AccountStatus" ADD VALUE IF NOT EXISTS 'INACTIVE';

-- Per-account brute-force protection (complements per-IP rate limiting).
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "failedLoginAttempts" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "lockedUntil" TIMESTAMP(3);
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "deactivatedAt" TIMESTAMP(3);

