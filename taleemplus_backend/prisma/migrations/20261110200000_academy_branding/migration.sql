-- Academy white-label branding: contact email + stored logo image.
-- Additive only; existing rows keep NULLs and the legacy "logo" URL column
-- remains as a fallback.
ALTER TABLE "academies" ADD COLUMN "email" TEXT;
ALTER TABLE "academies" ADD COLUMN "logoData" BYTEA;
ALTER TABLE "academies" ADD COLUMN "logoMimeType" TEXT;
ALTER TABLE "academies" ADD COLUMN "logoUpdatedAt" TIMESTAMP(3);
