# TaleemPlus database schema

PostgreSQL (Neon in production) managed with Prisma 5. Source of truth: `taleemplus_backend/prisma/schema.prisma`; this file is generated from it.

Conventions: UUID primary keys; every tenant table has `academyId` (cascade delete with the academy); dates are `timestamp(3)` UTC except `attendance_records.logDate` (`YYYY-MM-DD` text). Uploaded file bytes are **not** in the database (only metadata in `stored_files`); the payment QR and fee-proof images are small `bytea` columns.

## Entity relationships (main)

```
Academy 1─* User (role ADMIN|TEACHER|STUDENT|PARENT)
User(PARENT) *─* User(STUDENT)            via parent_student_relationships
Academy 1─* ClassSection 1─* ClassSectionEnrollment *─1 User(STUDENT)
Academy 1─* Class (subject offering) ─ primaryTeacher → User(TEACHER)
Class 1─* StudentEnrollment *─1 User(STUDENT)
Class 1─* AttendanceRecord (unique class+student+logDate)
Class 1─* Quiz 1─* QuizQuestion ; Quiz 1─* TestMark (unique quiz+student)
Class 1─* TimetableSlot ; Class 1─* SharedResource ; Class 1─* Assignment 1─* AssignmentSubmission
User(STUDENT) 1─* FeeChallan (unique academy+student+billingPeriod) 1─* FeePaymentProof
Academy 1─* StoredFile (category + ownerId → resource/assignment/submission/quiz/user)
```

## Enum Role

ADMIN, TEACHER, STUDENT, PARENT

## Enum AccountStatus

ACTIVE, PENDING, REJECTED, INACTIVE

## Enum AttendanceStatus

PRESENT, ABSENT, LATE, LEAVE

## Enum FeeStatus

PENDING, PAID, OVERDUE

## Enum PaymentProofStatus

PENDING, VERIFIED, REJECTED

## Enum LegacyMappingStatus

PENDING, MAPPED, SKIPPED, FAILED

## Academy (`academies`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| code | String | @unique |
| name | String |  |
| address | String? |  |
| phone | String? |  |
| logo | String? |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| paymentQrData | Bytes? |  |
| paymentQrMimeType | String? |  |
| paymentProvider | String? |  |
| paymentAccountTitle | String? |  |
| paymentAccountDetails | String? |  |
| paymentQrEnabled | Boolean | @default(false) |
| legacyFirebaseUid | String? | @unique |
| academicStructure | Json? |  |
| latitude | Decimal? | @db.Decimal(9, 6) |
| longitude | Decimal? | @db.Decimal(9, 6) |
| locationLabel | String? |  |
| bankName | String? |  |
| bankAccountNumber | String? |  |
| bankIban | String? |  |
| paymentInstructions | String? |  |

## User (`users`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| email | String | @unique |
| passwordHash | String |  |
| fullName | String |  |
| studentCode | String? | @unique |
| rollNumber | String? |  |
| phoneNumber | String? |  |
| role | Role |  |
| accountStatus | AccountStatus | @default(PENDING) |
| academyId | String |  |
| assignedSections | String[] | @default([]) |
| legacyFirebaseUid | String? | @unique |
| subject | String? |  |
| extraInfo | String? |  |
| joiningDate | DateTime? |  |
| securityQuestion | String? |  |
| securityAnswerHash | String? |  |
| failedLoginAttempts | Int | @default(0) |
| lockedUntil | DateTime? |  |
| deactivatedAt | DateTime? |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| academy | → Academy | onDelete: Cascade |
| parentLinks | → ParentStudent[] |  |
| studentLinks | → ParentStudent[] |  |
| markedAttendance | → AttendanceRecord[] |  |
| studentAttendance | → AttendanceRecord[] |  |
| taughtClasses | → Class[] |  |
| feeChallans | → FeeChallan[] |  |
| reviewedPaymentProofs | → FeePaymentProof[] |  |
| createdNotices | → Announcement[] |  |
| createdQuizzes | → Quiz[] |  |
| testMarks | → TestMark[] |  |
| resources | → SharedResource[] |  |
| askedQueries | → StudentQuery[] |  |
| answeredQueries | → StudentQuery[] |  |
| ocrDocs | → OcrDocument[] |  |
| notifications | → Notification[] |  |
| timetableSlots | → TimetableSlot[] |  |
| uploadedFiles | → StoredFile[] |  |
| createdAssignments | → Assignment[] |  |
| assignmentSubmissions | → AssignmentSubmission[] |  |
| _index_ | | `@@index([academyId, role])` |
| _index_ | | `@@index([academyId, accountStatus, role])` |

## ParentStudent (`parent_student_relationships`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| parentId | String |  |
| studentId | String |  |
| createdAt | DateTime | @default(now()) |
| parent | → User | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| _unique_ | | `@@unique([parentId, studentId])` |

## Class (`classes`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| className | String |  |
| section | String |  |
| subject | String |  |
| program | String? |  |
| classSectionId | String? |  |
| primaryTeacherId | String? |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| academy | → Academy | onDelete: Cascade |
| classSection | → ClassSection? | onDelete: SetNull |
| primaryTeacher | → User? | onDelete: SetNull |
| _unique_ | | `@@unique([academyId, className, section, subject])` |
| _index_ | | `@@index([academyId, classSectionId])` |

## ClassSection (`class_sections`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| className | String |  |
| program | String | @default("") |
| section | String |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| academy | → Academy | onDelete: Cascade |
| _unique_ | | `@@unique([academyId, className, program, section])` |
| _index_ | | `@@index([academyId, className])` |

## ClassSectionEnrollment (`class_section_enrollments`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| sectionId | String |  |
| studentId | String |  |
| rollNumber | String? |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| section | → ClassSection | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| _unique_ | | `@@unique([sectionId, studentId])` |
| _unique_ | | `@@unique([sectionId, rollNumber])` |
| _index_ | | `@@index([studentId])` |

## ClassReport (`class_reports`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| classLabel | String |  |
| generatedAt | DateTime | @default(now()) |
| totalStudents | Int | @default(0) |
| present | Int | @default(0) |
| absent | Int | @default(0) |
| feePaid | Int | @default(0) |
| feePending | Int | @default(0) |
| feePaidAmount | Decimal | @default(0) @db.Decimal(12, 2) |
| feePendingAmount | Decimal | @default(0) @db.Decimal(12, 2) |
| createdAt | DateTime | @default(now()) |
| academy | → Academy | onDelete: Cascade |
| _index_ | | `@@index([academyId, generatedAt])` |

## StudentEnrollment (`student_enrollments`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| classId | String |  |
| studentId | String |  |
| rollNumber | String? |  |
| createdAt | DateTime | @default(now()) |
| class | → Class | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| _unique_ | | `@@unique([classId, studentId])` |
| _index_ | | `@@index([studentId])` |

## AttendanceRecord (`attendance_records`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| classId | String |  |
| studentId | String |  |
| logDate | String |  |
| status | AttendanceStatus |  |
| markedById | String |  |
| recordedAt | DateTime | @default(now()) |
| academy | → Academy | onDelete: Cascade |
| class | → Class | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| markedBy | → User | onDelete: Cascade |
| _unique_ | | `@@unique([classId, studentId, logDate])` |
| _index_ | | `@@index([academyId, logDate])` |
| _index_ | | `@@index([academyId, classId, logDate])` |
| _index_ | | `@@index([studentId, logDate])` |

## FeeChallan (`fee_challans`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| challanNumber | String | @unique |
| studentId | String |  |
| studentName | String |  |
| fatherName | String? |  |
| classLabel | String |  |
| rollNumber | String? |  |
| issueDate | DateTime | @default(now()) |
| dueDate | DateTime |  |
| monthlyFee | Decimal | @db.Decimal(10, 2) |
| admissionFee | Decimal | @default(0) @db.Decimal(10, 2) |
| examFee | Decimal | @default(0) @db.Decimal(10, 2) |
| transportFee | Decimal | @default(0) @db.Decimal(10, 2) |
| fine | Decimal | @default(0) @db.Decimal(10, 2) |
| totalAmount | Decimal | @db.Decimal(10, 2) |
| status | FeeStatus | @default(PENDING) |
| paidAt | DateTime? |  |
| billingPeriod | String? |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| academy | → Academy | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| _unique_ | | `@@unique([academyId, studentId, billingPeriod])` |
| _index_ | | `@@index([academyId, status, dueDate])` |

## FeePaymentProof (`fee_payment_proofs`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| challanId | String |  |
| submittedById | String |  |
| reviewedById | String? |  |
| imageData | Bytes |  |
| mimeType | String |  |
| status | PaymentProofStatus | @default(PENDING) |
| submittedAt | DateTime | @default(now()) |
| reviewedAt | DateTime? |  |
| academy | → Academy | onDelete: Cascade |
| challan | → FeeChallan | onDelete: Cascade |
| submittedBy | → User | onDelete: Cascade |
| reviewedBy | → User? | onDelete: SetNull |
| _index_ | | `@@index([academyId, status, submittedAt])` |

## Announcement (`announcements`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| title | String |  |
| message | String |  |
| targetRoles | String[] | @default(["all"]) |
| createdById | String |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| academy | → Academy | onDelete: Cascade |
| createdBy | → User | onDelete: Cascade |
| _index_ | | `@@index([academyId, createdAt])` |

## Quiz (`quizzes`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| classId | String |  |
| classLabel | String |  |
| title | String |  |
| subject | String |  |
| month | String? |  |
| session | String? |  |
| chapter | String? |  |
| difficulty | String? |  |
| totalMarks | Int |  |
| testDate | DateTime? |  |
| instructions | String? |  |
| createdById | String |  |
| createdAt | DateTime | @default(now()) |
| academy | → Academy | onDelete: Cascade |
| class | → Class | onDelete: Cascade |
| createdBy | → User | onDelete: Cascade |
| _index_ | | `@@index([academyId, classId, createdAt])` |

## QuizQuestion (`quiz_questions`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| quizId | String |  |
| text | String |  |
| type | String | @default("short") |
| options | String[] | @default([]) |
| correctIndex | Int? |  |
| marks | Int | @default(5) |
| gradingKeywords | String[] | @default([]) |
| quiz | → Quiz | onDelete: Cascade |

## TestMark (`test_marks`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| quizId | String |  |
| studentId | String |  |
| studentName | String |  |
| classId | String |  |
| subject | String |  |
| month | String? |  |
| marksObtained | Float |  |
| totalMarks | Float |  |
| percentage | Float |  |
| gradeLetter | String |  |
| teacherFeedback | String? |  |
| updatedAt | DateTime | @updatedAt |
| academy | → Academy | onDelete: Cascade |
| quiz | → Quiz | onDelete: Cascade |
| class | → Class | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| _unique_ | | `@@unique([quizId, studentId])` |
| _index_ | | `@@index([academyId, classId, month])` |

## SharedResource (`shared_resources`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| classId | String |  |
| teacherId | String |  |
| title | String |  |
| description | String? |  |
| fileUrl | String? |  |
| contentText | String? |  |
| fileName | String? |  |
| mimeType | String? |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @default(now()) @updatedAt |
| academy | → Academy | onDelete: Cascade |
| class | → Class | onDelete: Cascade |
| teacher | → User | onDelete: Cascade |
| _index_ | | `@@index([academyId, classId, createdAt])` |

## StudentQuery (`student_queries`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| classId | String |  |
| studentId | String |  |
| teacherId | String? |  |
| question | String |  |
| answer | String? |  |
| isResolved | Boolean | @default(false) |
| createdAt | DateTime | @default(now()) |
| answeredAt | DateTime? |  |
| academy | → Academy | onDelete: Cascade |
| class | → Class | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| teacher | → User? | onDelete: SetNull |
| _index_ | | `@@index([academyId, isResolved, createdAt])` |
| _index_ | | `@@index([teacherId, isResolved, createdAt])` |
| _index_ | | `@@index([studentId, createdAt])` |

## OcrDocument (`ocr_documents`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String? |  |
| createdById | String |  |
| createdByName | String? |  |
| title | String |  |
| extractedText | String |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @default(now()) @updatedAt |
| academy | → Academy? | onDelete: SetNull |
| createdBy | → User | onDelete: Cascade |
| _index_ | | `@@index([academyId, createdById, createdAt])` |
| _index_ | | `@@index([createdById, createdAt])` |

## Notification (`notifications`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| recipientId | String |  |
| title | String |  |
| message | String |  |
| type | String | @default("general") |
| isRead | Boolean | @default(false) |
| createdAt | DateTime | @default(now()) |
| academy | → Academy | onDelete: Cascade |
| recipient | → User | onDelete: Cascade |
| _index_ | | `@@index([academyId, recipientId, createdAt])` |
| _index_ | | `@@index([academyId, recipientId, isRead])` |

## TimetableSlot (`timetable_slots`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| classId | String? |  |
| section | String |  |
| dayOfWeek | String |  |
| startTime | String |  |
| endTime | String |  |
| subject | String |  |
| teacherId | String? |  |
| dayOfWeekInt | Int? |  |
| startMinutes | Int? |  |
| endMinutes | Int? |  |
| room | String? |  |
| semester | String? |  |
| isBreak | Boolean | @default(false) |
| effectiveFrom | DateTime? |  |
| effectiveTo | DateTime? |  |
| createdAt | DateTime | @default(now()) |
| academy | → Academy | onDelete: Cascade |
| class | → Class? | onDelete: Cascade |
| teacher | → User? | onDelete: SetNull |
| _index_ | | `@@index([academyId, classId, dayOfWeekInt])` |
| _index_ | | `@@index([academyId, teacherId, dayOfWeekInt])` |

## RefreshToken (`refresh_tokens`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| userId | String |  |
| token | String | @unique |
| expiresAt | DateTime |  |
| revoked | Boolean | @default(false) |
| createdAt | DateTime | @default(now()) |
| user | → User | onDelete: Cascade |
| _index_ | | `@@index([userId, revoked])` |

## LegacyIdMap (`legacy_id_map`)

| Field | Type | Notes |
|---|---|---|
| collection | String | @map("collection") |
| legacyId | String | @map("legacy_id") |
| targetTable | String | @map("target_table") |
| targetId | String | @map("target_id") |
| status | LegacyMappingStatus | @default(PENDING) |
| notes | String? |  |
| createdAt | DateTime | @default(now()) @map("created_at") |
| updatedAt | DateTime | @updatedAt @map("updated_at") |
| _id_ | | `@@id([collection, legacyId])` |
| _index_ | | `@@index([targetTable, targetId])` |

## StoredFile (`stored_files`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| category | String |  |
| ownerId | String |  |
| originalName | String |  |
| storageKey | String | @unique |
| storageDriver | String |  |
| mimeType | String |  |
| sizeBytes | Int |  |
| sha256 | String |  |
| description | String? |  |
| uploadedById | String |  |
| createdAt | DateTime | @default(now()) |
| academy | → Academy | onDelete: Cascade |
| uploadedBy | → User | onDelete: Cascade |
| _index_ | | `@@index([academyId, category, ownerId])` |

## Assignment (`assignments`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| academyId | String |  |
| classId | String |  |
| title | String |  |
| instructions | String? |  |
| dueAt | DateTime |  |
| maxMarks | Int? |  |
| allowResubmission | Boolean | @default(true) |
| createdById | String |  |
| createdAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| academy | → Academy | onDelete: Cascade |
| class | → Class | onDelete: Cascade |
| createdBy | → User | onDelete: Cascade |
| _index_ | | `@@index([academyId, classId, dueAt])` |

## AssignmentSubmission (`assignment_submissions`)

| Field | Type | Notes |
|---|---|---|
| id | String | @id @default(uuid()) |
| assignmentId | String |  |
| studentId | String |  |
| note | String? |  |
| submittedAt | DateTime | @default(now()) |
| updatedAt | DateTime | @updatedAt |
| marks | Float? |  |
| feedback | String? |  |
| gradedAt | DateTime? |  |
| assignment | → Assignment | onDelete: Cascade |
| student | → User | onDelete: Cascade |
| _unique_ | | `@@unique([assignmentId, studentId])` |
| _index_ | | `@@index([studentId])` |

