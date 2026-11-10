-- CreateEnum
CREATE TYPE "LinkRequestStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateTable
CREATE TABLE "parent_link_requests" (
    "id" TEXT NOT NULL,
    "academyId" TEXT NOT NULL,
    "parentId" TEXT NOT NULL,
    "studentId" TEXT,
    "childName" TEXT NOT NULL,
    "childEmail" TEXT,
    "rollNumber" TEXT,
    "status" "LinkRequestStatus" NOT NULL DEFAULT 'PENDING',
    "note" TEXT,
    "decidedById" TEXT,
    "decidedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "parent_link_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "parent_link_requests_academyId_status_idx" ON "parent_link_requests"("academyId", "status");

-- CreateIndex
CREATE INDEX "parent_link_requests_parentId_status_idx" ON "parent_link_requests"("parentId", "status");

-- AddForeignKey
ALTER TABLE "parent_link_requests" ADD CONSTRAINT "parent_link_requests_parentId_fkey" FOREIGN KEY ("parentId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "parent_link_requests" ADD CONSTRAINT "parent_link_requests_studentId_fkey" FOREIGN KEY ("studentId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

