-- Profile parity and self-service password recovery fields.
ALTER TABLE "users"
ADD COLUMN "rollNumber" TEXT,
ADD COLUMN "securityQuestion" TEXT,
ADD COLUMN "securityAnswerHash" TEXT;

-- Roll numbers are unique per academy when present. Partial indexes keep
-- existing users without a roll number valid.
CREATE UNIQUE INDEX "users_academyId_rollNumber_key"
ON "users"("academyId", "rollNumber")
WHERE "rollNumber" IS NOT NULL;

-- Break periods have no class offering attached. Make classId optional so
-- breaks can be represented without inventing a fake class.
ALTER TABLE "timetable_slots" ALTER COLUMN "classId" DROP NOT NULL;
