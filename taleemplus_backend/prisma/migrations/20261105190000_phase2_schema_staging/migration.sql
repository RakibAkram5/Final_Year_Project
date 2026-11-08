-- CreateEnum
CREATE TYPE "LegacyMappingStatus" AS ENUM ('PENDING', 'MAPPED', 'SKIPPED', 'FAILED');

-- DropForeignKey
ALTER TABLE "timetable_slots" DROP CONSTRAINT "timetable_slots_teacherId_fkey";

-- AlterTable
ALTER TABLE "academies" ADD COLUMN     "academicStructure" JSONB,
ADD COLUMN     "legacyFirebaseUid" TEXT;

-- AlterTable
ALTER TABLE "classes" ADD COLUMN     "classSectionId" TEXT,
ADD COLUMN     "program" TEXT;

-- AlterTable
ALTER TABLE "ocr_documents" ADD COLUMN     "academyId" TEXT,
ADD COLUMN     "createdByName" TEXT,
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "shared_resources" ADD COLUMN     "contentText" TEXT,
ADD COLUMN     "fileName" TEXT,
ADD COLUMN     "mimeType" TEXT,
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ALTER COLUMN "fileUrl" DROP NOT NULL;

-- AlterTable
ALTER TABLE "timetable_slots" ADD COLUMN     "dayOfWeekInt" INTEGER,
ADD COLUMN     "effectiveFrom" TIMESTAMP(3),
ADD COLUMN     "effectiveTo" TIMESTAMP(3),
ADD COLUMN     "endMinutes" INTEGER,
ADD COLUMN     "isBreak" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "room" TEXT,
ADD COLUMN     "semester" TEXT,
ADD COLUMN     "startMinutes" INTEGER,
ALTER COLUMN "teacherId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "extraInfo" TEXT,
ADD COLUMN     "joiningDate" TIMESTAMP(3),
ADD COLUMN     "legacyFirebaseUid" TEXT,
ADD COLUMN     "subject" TEXT;

-- CreateTable
CREATE TABLE "class_sections" (
    "id" TEXT NOT NULL,
    "academyId" TEXT NOT NULL,
    "className" TEXT NOT NULL,
    "program" TEXT NOT NULL DEFAULT '',
    "section" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "class_sections_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "class_section_enrollments" (
    "id" TEXT NOT NULL,
    "sectionId" TEXT NOT NULL,
    "studentId" TEXT NOT NULL,
    "rollNumber" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "class_section_enrollments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "class_reports" (
    "id" TEXT NOT NULL,
    "academyId" TEXT NOT NULL,
    "classLabel" TEXT NOT NULL,
    "generatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "totalStudents" INTEGER NOT NULL DEFAULT 0,
    "present" INTEGER NOT NULL DEFAULT 0,
    "absent" INTEGER NOT NULL DEFAULT 0,
    "feePaid" INTEGER NOT NULL DEFAULT 0,
    "feePending" INTEGER NOT NULL DEFAULT 0,
    "feePaidAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "feePendingAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "class_reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "legacy_id_map" (
    "collection" TEXT NOT NULL,
    "legacy_id" TEXT NOT NULL,
    "target_table" TEXT NOT NULL,
    "target_id" TEXT NOT NULL,
    "status" "LegacyMappingStatus" NOT NULL DEFAULT 'PENDING',
    "notes" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "legacy_id_map_pkey" PRIMARY KEY ("collection","legacy_id")
);

-- CreateIndex
CREATE INDEX "class_sections_academyId_className_idx" ON "class_sections"("academyId", "className");

-- CreateIndex
CREATE UNIQUE INDEX "class_sections_academyId_className_program_section_key" ON "class_sections"("academyId", "className", "program", "section");

-- CreateIndex
CREATE INDEX "class_section_enrollments_studentId_idx" ON "class_section_enrollments"("studentId");

-- CreateIndex
CREATE UNIQUE INDEX "class_section_enrollments_sectionId_studentId_key" ON "class_section_enrollments"("sectionId", "studentId");

-- CreateIndex
CREATE UNIQUE INDEX "class_section_enrollments_sectionId_rollNumber_key" ON "class_section_enrollments"("sectionId", "rollNumber");

-- CreateIndex
CREATE INDEX "class_reports_academyId_generatedAt_idx" ON "class_reports"("academyId", "generatedAt");

-- CreateIndex
CREATE INDEX "legacy_id_map_target_table_target_id_idx" ON "legacy_id_map"("target_table", "target_id");

-- CreateIndex
CREATE UNIQUE INDEX "academies_legacyFirebaseUid_key" ON "academies"("legacyFirebaseUid");

-- CreateIndex
CREATE INDEX "announcements_academyId_createdAt_idx" ON "announcements"("academyId", "createdAt");

-- CreateIndex
CREATE INDEX "attendance_records_academyId_logDate_idx" ON "attendance_records"("academyId", "logDate");

-- CreateIndex
CREATE INDEX "attendance_records_academyId_classId_logDate_idx" ON "attendance_records"("academyId", "classId", "logDate");

-- CreateIndex
CREATE INDEX "attendance_records_studentId_logDate_idx" ON "attendance_records"("studentId", "logDate");

-- CreateIndex
CREATE INDEX "classes_academyId_classSectionId_idx" ON "classes"("academyId", "classSectionId");

-- CreateIndex
CREATE INDEX "fee_challans_academyId_status_dueDate_idx" ON "fee_challans"("academyId", "status", "dueDate");

-- CreateIndex
CREATE INDEX "notifications_academyId_recipientId_createdAt_idx" ON "notifications"("academyId", "recipientId", "createdAt");

-- CreateIndex
CREATE INDEX "notifications_academyId_recipientId_isRead_idx" ON "notifications"("academyId", "recipientId", "isRead");

-- CreateIndex
CREATE INDEX "ocr_documents_academyId_createdById_createdAt_idx" ON "ocr_documents"("academyId", "createdById", "createdAt");

-- CreateIndex
CREATE INDEX "ocr_documents_createdById_createdAt_idx" ON "ocr_documents"("createdById", "createdAt");

-- CreateIndex
CREATE INDEX "quizzes_academyId_classId_createdAt_idx" ON "quizzes"("academyId", "classId", "createdAt");

-- CreateIndex
CREATE INDEX "refresh_tokens_userId_revoked_idx" ON "refresh_tokens"("userId", "revoked");

-- CreateIndex
CREATE INDEX "shared_resources_academyId_classId_createdAt_idx" ON "shared_resources"("academyId", "classId", "createdAt");

-- CreateIndex
CREATE INDEX "student_enrollments_studentId_idx" ON "student_enrollments"("studentId");

-- CreateIndex
CREATE INDEX "student_queries_academyId_isResolved_createdAt_idx" ON "student_queries"("academyId", "isResolved", "createdAt");

-- CreateIndex
CREATE INDEX "student_queries_teacherId_isResolved_createdAt_idx" ON "student_queries"("teacherId", "isResolved", "createdAt");

-- CreateIndex
CREATE INDEX "student_queries_studentId_createdAt_idx" ON "student_queries"("studentId", "createdAt");

-- CreateIndex
CREATE INDEX "test_marks_academyId_classId_month_idx" ON "test_marks"("academyId", "classId", "month");

-- CreateIndex
CREATE INDEX "timetable_slots_academyId_classId_dayOfWeekInt_idx" ON "timetable_slots"("academyId", "classId", "dayOfWeekInt");

-- CreateIndex
CREATE INDEX "timetable_slots_academyId_teacherId_dayOfWeekInt_idx" ON "timetable_slots"("academyId", "teacherId", "dayOfWeekInt");

-- CreateIndex
CREATE UNIQUE INDEX "users_legacyFirebaseUid_key" ON "users"("legacyFirebaseUid");

-- CreateIndex
CREATE INDEX "users_academyId_role_idx" ON "users"("academyId", "role");

-- CreateIndex
CREATE INDEX "users_academyId_accountStatus_role_idx" ON "users"("academyId", "accountStatus", "role");

-- AddForeignKey
ALTER TABLE "classes" ADD CONSTRAINT "classes_classSectionId_fkey" FOREIGN KEY ("classSectionId") REFERENCES "class_sections"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "class_sections" ADD CONSTRAINT "class_sections_academyId_fkey" FOREIGN KEY ("academyId") REFERENCES "academies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "class_section_enrollments" ADD CONSTRAINT "class_section_enrollments_sectionId_fkey" FOREIGN KEY ("sectionId") REFERENCES "class_sections"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "class_section_enrollments" ADD CONSTRAINT "class_section_enrollments_studentId_fkey" FOREIGN KEY ("studentId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "class_reports" ADD CONSTRAINT "class_reports_academyId_fkey" FOREIGN KEY ("academyId") REFERENCES "academies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ocr_documents" ADD CONSTRAINT "ocr_documents_academyId_fkey" FOREIGN KEY ("academyId") REFERENCES "academies"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "timetable_slots" ADD CONSTRAINT "timetable_slots_teacherId_fkey" FOREIGN KEY ("teacherId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

