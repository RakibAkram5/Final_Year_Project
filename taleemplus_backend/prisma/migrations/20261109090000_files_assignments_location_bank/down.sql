-- Manual rollback for 20261109090000_files_assignments_location_bank.
-- NOT run by `prisma migrate`. Only use after backing up: it deletes every
-- assignment, submission and file-metadata row (blob objects must be removed
-- separately) and the academy location/bank columns.
DROP TABLE IF EXISTS "assignment_submissions";
DROP TABLE IF EXISTS "assignments";
DROP TABLE IF EXISTS "stored_files";
ALTER TABLE "academies"
  DROP COLUMN IF EXISTS "bankAccountNumber",
  DROP COLUMN IF EXISTS "bankIban",
  DROP COLUMN IF EXISTS "bankName",
  DROP COLUMN IF EXISTS "latitude",
  DROP COLUMN IF EXISTS "locationLabel",
  DROP COLUMN IF EXISTS "longitude",
  DROP COLUMN IF EXISTS "paymentInstructions";
