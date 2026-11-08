# Firebase Migration Inventory

Status: Phase 0 inventory, read-only  
Repository: `H:\Final Version`  
Branch: `fix/ci-pipeline`  
Baseline commit: `9d42d9ff01d1a9abde914f8e61858aae2f2bd5a8`  
Inventory date: 2026-11-05

This document records the current Firebase/Firestore footprint before any migration code is written. It is an inventory, not an implementation approval. PostgreSQL/REST is treated as the intended system of record unless a later decision explicitly keeps a Firebase capability.

## 1. Executive Summary

- Firebase usage is almost entirely Firestore. The client imports `cloud_firestore` in **25 Dart files** and `firebase_core` in **2 Dart files** (`lib/main.dart`, `lib/firebase_options.dart`).
- There is **no active Firebase Authentication, Storage, Messaging, Analytics, Remote Config, or Functions integration** in `lib/`. Authentication is REST/JWT based.
- Firestore is currently both a live data source and a source of Firestore-specific types embedded in otherwise REST-backed models.
- The Firebase project is not operational from this build: Dart options use placeholder credentials, Android `google-services.json` is absent, the Google Services Gradle plugin is commented out, and no Firebase Auth session is created.
- If a real Firebase project and the committed `firestore.rules` were applied as-is, the current app would not be authorized for Firestore reads because the rules depend on `request.auth` and a `/users/{request.auth.uid}` profile. The app never signs into Firebase Auth.
- The repository contains placeholder migration scripts and empty export files. They are not a usable export/import path and must not be run against production data.
- Firestore tenant keys are inconsistent. Some admin screens and services use the admin's user ID where an academy ID is expected; other screens use the PostgreSQL academy UUID. This must be resolved before any historical-data import.
- Remote Firestore contents are unknown. No Firebase credentials, service account, or export was available, so no remote collection counts or field-level legacy data could be inspected.

## 2. Snapshot and Evidence

Read-only checks performed:

- Repository status, branch, HEAD, and untracked/modified file preservation.
- `pubspec.yaml` dependency inspection.
- Import scans across `lib/`.
- Firestore API/type scans across `lib/`.
- Collection-reference scans.
- Firestore rules and indexes inspection.
- `firebase.json`, `.firebaserc`, Android/iOS Firebase configuration inspection.
- Existing migration scripts and `data_export/` inspection.
- Backend Prisma schema and route/controller inspection.
- Previous build/test results retained from `TALEEMPLUS_PROJECT_AUDIT.md`: `flutter analyze` clean, 12 Flutter tests passed, 17 backend tests passed, web release and debug APK built, `/health` returned HTTP 200 with database connected.

Limits:

- No Firebase service account or authenticated Firebase CLI session.
- No remote data export or collection counts.
- No production credentials or domain-user credentials.
- No Android device/emulator.
- No secrets are reproduced in this document.

## 3. Dependency and Platform Inventory

### 3.1 Dart dependencies

| Package | Version constraint | Current use | Migration consequence |
|---|---|---|---|
| `firebase_core` | `^3.1.0` | `Firebase.initializeApp` at startup | Must be removed or made conditional after Firestore is gone. |
| `firebase_auth` | `^5.1.0` | No imports or calls found in `lib/` | Unused by current application auth; likely removable. |
| `cloud_firestore` | `^5.0.1` | 25 importing files, 11 collections referenced | Primary migration target. |
| `google_mlkit_text_recognition` | `^0.13.0` | On-device OCR | Not Firebase; retain unless replaced separately. |

No Firebase Storage, Messaging, Analytics, Remote Config, Functions, Crashlytics, or App Check package is declared.

### 3.2 Initialization and configuration

| Item | Current state |
|---|---|
| Startup initialization | `lib/main.dart` calls `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` before `runApp`. |
| Dart options | `lib/firebase_options.dart` contains placeholder API keys/app IDs for web, Android, iOS, macOS, and Windows. |
| Firebase project metadata | `firebase.json` and `.firebaserc` reference project `taleemplus-40755`. |
| Android config | `android/app/google-services.json` is absent. |
| iOS config | `ios/Runner/GoogleService-Info.plist` is absent. |
| Android Gradle plugin | `com.google.gms.google-services` is declared but the application plugin is commented out in `android/app/build.gradle.kts`. |
| Firestore rules | `firestore.rules` exists and assumes Firebase Auth users plus `/users/{uid}` profile documents. |
| Firestore indexes | `firestore.indexes.json` contains indexes for notifications, announcements, attendance, and fee challans. |
| Firebase Hosting | `firebase.json` points Hosting at `build/web`. |
| Android release networking | Main manifest lacks `INTERNET`; only debug/profile manifests declare it. This is independent of Firebase removal but blocks release REST access. |

### 3.3 Authentication mismatch

The application authenticates against the Express backend with JWT access/refresh tokens. No code signs in to Firebase Auth. Therefore:

- `request.auth` is absent for Firestore requests made by this build.
- `firestore.rules` calls such as `isApproved()`, `sameAcademy()`, and owner checks cannot succeed without a Firebase Auth user and matching `/users/{uid}` document.
- Firestore's current role in the build is effectively “unauthenticated client storage,” not a secure extension of REST auth.
- Firebase Auth cannot be removed as a “migration prerequisite” by simply deleting it; it is already unused. Removing Firestore removes the last Firebase runtime dependency.

## 4. Firestore Collection Inventory

The following collections are referenced by current Dart code. “Current access” distinguishes live Firestore I/O from models that only borrow Firestore types.

| Collection | Document key / shape | Fields observed or written | Current access | Intended REST/Prisma destination |
|---|---|---|---|---|
| `academy_settings` | Doc ID = academy identifier | `academic_structure` map, defaults, classes/programs/groups | Read, seed, watch, update in `AcademicStructureService` | No current backend model. Candidate: `Academy.academicStructure Json`. |
| `announcements` | Auto ID | `academy_id`, `title`, `message`, `target_roles`, `created_by_uid`, `created_by_name`, `created_at`, `updated_at` | Read/watch/create/update/delete in `AnnouncementService`; admin/teacher/student/parent widgets | Partial REST exists at `/announcements`; client currently does not use it. |
| `class_reports` | App-generated ID | `academy_id`, `class_label`, `generated_at`, `total_students`, `present`, `absent`, `fee_paid`, `fee_pending`, `fee_paid_amount`, `fee_pending_amount` | Read/watch/create/delete in `ClassReportRepository` | No backend model/endpoint. |
| `class_sections` | Auto ID | `academy_id`, `class_name`, `program`, `section`, `student_ids`, `student_names`, `created_at`, `updated_at` | Read/watch/create/update/delete in `ClassSectionRepository` | No backend model/endpoint; likely `ClassSection` + roster relation. |
| `classes` | Firestore class ID | `academy_id`, `class_name`, `section`, `subject`, `primary_teacher_id/name/email`, `student_ids`, `student_names`, timestamps | Direct read/cascade update/delete in `ClassSectionRepository`; REST class list uses the same model shape | Prisma `Class` + `StudentEnrollment`; REST exists but edit/unenroll is incomplete. |
| `learning_resources` | Auto ID | `academy_id`, `class_id`, `teacher_id`, `teacher_name`, `title`, `description`, `file_url`, `created_at` | Read/watch/create in `ClassroomService`; OCR publish creates resources | Prisma `SharedResource`; REST exists under doubled paths and requires `fileUrl`. |
| `notifications` | Auto ID | `id`, `academy_id`, `recipient_id`, `title`, `message`, `type`, `is_read`, `created_at` | Read/watch/create/batch-create/update in `NotificationService` | Prisma `Notification`; partial REST exists. |
| `ocr_documents` | Auto ID | `title`, `extracted_text`, `created_by_uid`, `created_by_name`, `created_at` | Read/watch/create/update/delete in `OcrFirestoreService` | Prisma `OcrDocument` exists but lacks `createdByName`, `updatedAt`, and `academyId`; no routes. |
| `student_queries` | Auto ID | `academy_id`, `class_id`, `student_id`, `student_name`, `teacher_id`, `question`, `answer`, `is_resolved`, `created_at`, `answered_at` | Read/watch/create/answer in `ClassroomService` | Prisma `StudentQuery`; REST exists under doubled paths. |
| `timetables` | App-generated slot ID | `academy_id`, `is_break`, `class_id`, `class_name`, `section`, `subject`, `teacher_id`, `teacher_name`, `day_of_week` integer, `start_minutes`, `end_minutes`, `room`, `semester`, `effective_from`, `effective_to`, timestamps | Read/watch/create/update/delete/batch-delete in `TimetableService` | Prisma `TimetableSlot`; API exists but contract differs and Flutter does not call it. |
| `users` | Firebase user UID | Full user/academy profile fields, `academy_id`, `academy_code`, `linked_children`, `roll_number`, `student_code`, `subject`, `extra_info`, timestamps | Read in test-paper PDF; direct legacy update in `admin_dashboard` | Prisma `User` + `Academy`; auth/user REST is primary, but profile fields are incomplete. |

Collections named in `firestore.rules` but not referenced by current Dart modules:

- `quizzes`
- `test_marks`
- `attendance_records`
- `fee_challans`
- `fee_invoices`
- `password_recovery`

These appear to be historical or reserved and must be included in the remote-data decision. `AttendanceRecord` and `FeeChallanModel` comments still mention Firestore paths, but current repositories use REST.

### 4.1 Firestore access files

Actual Firestore I/O is confined to these 10 files:

1. `lib/data/remote/academic_structure_service.dart`
2. `lib/data/remote/announcement_service.dart`
3. `lib/data/remote/classroom_service.dart`
4. `lib/data/remote/notification_service.dart`
5. `lib/data/remote/pdf_generator_service.dart`
6. `lib/data/remote/timetable_service.dart`
7. `lib/data/repositories/class_report_repository.dart`
8. `lib/data/repositories/class_section_repository.dart`
9. `lib/features/admin/admin_dashboard.dart`
10. `lib/features/ocr/services/ocr_firestore_service.dart`

### 4.2 Firestore types in otherwise REST-backed models

The remaining 15 `cloud_firestore` imports are models that use `Timestamp` and/or `FieldValue` in serialization. Several currently receive REST maps and therefore fail or silently default dates.

| File | Firestore symbols | Notes |
|---|---|---|
| `lib/data/models/announcement.dart` | `Timestamp`, `FieldValue` | Also used by Firestore announcement service. |
| `lib/data/models/app_user.dart` | `Timestamp`, `FieldValue` | REST auth maps use ISO strings; Firestore profile serialization remains. |
| `lib/data/models/attendance_record.dart` | `Timestamp`, `FieldValue` | REST repository sends `DateTime` directly and class response uses Prisma camelCase. |
| `lib/data/models/class_entity.dart` | `Timestamp`, `FieldValue` | Used by both REST class list and Firestore section cascade. |
| `lib/data/models/class_report_model.dart` | `Timestamp` | Firestore-only report snapshots. |
| `lib/data/models/class_section.dart` | `Timestamp`, `FieldValue` | Firestore-only sections. |
| `lib/data/models/fee_challan_model.dart` | `Timestamp` | REST API returns ISO strings; dates default to `DateTime.now()`. |
| `lib/data/models/notification_model.dart` | `Timestamp` | Firestore-only notifications. |
| `lib/data/models/quiz_model.dart` | `Timestamp`, `FieldValue` | REST API returns ISO strings; `created_at` cast crashes list parsing. |
| `lib/data/models/quiz_submission_model.dart` | `Timestamp` | No current collection reference or service use; appears unused. |
| `lib/data/models/shared_resource.dart` | `Timestamp`, `FieldValue` | Firestore resource path; REST shape partially matches. |
| `lib/data/models/student_query.dart` | `Timestamp`, `FieldValue` | Firestore query path. |
| `lib/data/models/test_mark_model.dart` | `Timestamp` | REST marks path; guards timestamp on read. |
| `lib/data/models/timetable_slot.dart` | `Timestamp`, `FieldValue` | Firestore timetable path. |
| `lib/features/ocr/models/ocr_document_model.dart` | `Timestamp`, `FieldValue` | Firestore OCR path. |

## 5. Firestore-Specific Behavior That Must Be Replaced

| Behavior | Where used | REST replacement requirement |
|---|---|---|
| `Timestamp` conversion and type checks | All 15 model files | Parse ISO-8601 strings and accept legacy Timestamp-like maps only in migration scripts. |
| `FieldValue.serverTimestamp()` | Announcement, user, class, section, resource, query, quiz, timetable, OCR models | Backend should own timestamps; clients must not produce Firestore sentinels. |
| Auto-generated document IDs via `.add()` | Announcements, notifications, OCR, classroom resources/queries | Backend-generated UUIDs. |
| Deterministic document IDs | Attendance and quiz-submission comments/models | Backend uniqueness constraints. |
| Real-time `.snapshots()` streams | Announcements, notifications, academic structure, sections, reports, timetable, classroom, OCR | Polling, refresh-after-mutation, or explicit one-shot streams. Realtime semantics require a product decision. |
| `whereIn` with ≤10 values | Timetable student/parent lookup | Backend query scoped by enrollment; no client-side chunk truncation. |
| Write batches/chunking | Notifications, class-section cascade | Backend transactions and explicit cascade endpoints. |
| Client-side sorting to avoid indexes | Announcements, notifications, OCR, reports, sections | Backend ordering plus database indexes. |
| Security rules and `/users` profile lookup | `firestore.rules` | Backend role/tenant middleware; no client-side authorization assumptions. |
| Direct client writes | Multiple services/screens | All mutations through REST; no Firestore rules as the sole guard. |

## 6. Identity and Tenant Mapping

### 6.1 Identity models

| Identity | Current meaning | Risk |
|---|---|---|
| PostgreSQL `User.id` | UUID primary key | JWT `sub`/middleware identity and REST foreign keys. |
| PostgreSQL `Academy.id` | UUID primary key | Backend tenant key `req.academyId`. |
| PostgreSQL `Academy.code` | Human-readable join code | Used for registration; not an internal tenant key. |
| Firestore user document ID | Historically a Firebase Auth UID | Must be mapped to PostgreSQL `User.id`; cannot be assumed equal. |
| Firestore `academy_id` | Inconsistently an admin UID or a PostgreSQL academy UUID | Must be normalized to `Academy.id` or a documented legacy mapping. |
| Firestore `class_id`, `student_id`, `teacher_id`, `recipient_id` | Historically Firebase UIDs | Must be translated through an identity map. |

### 6.2 Observed tenant-key inconsistencies

| Location | Value used | Expected by target |
|---|---|---|
| `lib/features/admin/class_sections_screen.dart` | `currentUser.uid` for sections and academic structure | Academy UUID |
| `lib/features/admin/class_management_screen.dart` | `currentUser.uid` for section/structure providers and role lookups | Academy UUID |
| `lib/features/admin/user_management_screen.dart` | `admin.uid` for members, sections, children, challans | Academy UUID |
| `lib/features/admin/screens/class_reports_screen.dart` | `currentUser.uid` for reports and stats | Academy UUID |
| `lib/features/admin/screens/challan_generation_screen.dart` | `admin.uid` for sections, students, and challans | Academy UUID |
| `lib/features/admin/admin_dashboard.dart` | `user.uid` for member counts, stats, legacy `academy_id`; `user.academyId` for notification lookup | Academy UUID for all tenant data |
| `lib/data/remote/pdf_generator_service.dart` | `quiz.academyId` used as a `users/{id}` document ID | User ID for user document, or academy profile endpoint |
| Teacher/student/parent notification widgets | `user.academyId` | Academy UUID |
| REST repositories/services | Backend `req.academyId` | Academy UUID |

This is not a cosmetic inconsistency. Under the committed Firestore rules, documents keyed by an admin UID can be invisible to a reader whose `academy_id` is the PostgreSQL UUID, and vice versa. It also breaks cross-role visibility of announcements and notifications.

### 6.3 Migration identity requirements

Before importing historical data:

1. Build a source-to-target identity ledger for users, academies, classes, sections, and enrollment rows.
2. Store or derive a permanent mapping from legacy Firebase UID to PostgreSQL `User.id`.
3. Resolve each legacy admin UID to its PostgreSQL `Academy.id`.
4. Treat unmapped identities as errors, never as silently skipped records.
5. Preserve original source IDs in an audit table or nullable legacy-ID column for reconciliation.

## 7. Existing Migration Tooling

| File | What it actually does | Assessment |
|---|---|---|
| `scripts/export_firebase.js` | Creates empty JSON files under `data_export/`; does not connect to Firestore | Placeholder only. |
| `scripts/migrate_firebase_to_postgres.js` | Reads `data_export/users.json`, upserts users only, uses `uid` as PostgreSQL ID, inserts a fixed bcrypt placeholder hash for missing passwords, does not create academies or migrate any other collection | Not safe for real data; incompatible with UUID/tenant mapping and password security. |
| `scripts/verify_migration.js` | Prints four table counts only | Not a reconciliation or integrity check. |
| `data_export/*.json` | All files contain `[]` | No exported data is present. |

These scripts must be replaced or left unused. They must not be run against production data.

## 8. Security-Relevant Inventory

- Firestore rules are role/tenant aware in intent, but depend on Firebase Auth and legacy `/users/{uid}` documents that the current REST auth flow does not create.
- `ocr_documents` rules are owner-scoped by `created_by_uid`; the document has no `academy_id`.
- `password_recovery` is publicly readable by design in the rules; no current Dart code uses it.
- `notifications` creation is restricted to staff in rules, but the client can still attempt writes; authoritative checks must move to REST.
- `announcements` reads return all academy rows and filter target roles client-side, so role-targeted announcements are exposed to other academy roles.
- Firestore resources can contain external `file_url` values. The source bucket/lifetime is unknown.
- The release Android manifest lacks `INTERNET`, so a release build cannot reach either REST or Firestore even if configured.
- The committed `firestore.rules` reference `/users/{uid}` profile documents; if Firebase is retained temporarily, these documents become a security dependency, not just legacy data.

## 9. Unknowns Requiring Decisions

1. Does the production Firebase project still contain user, class, attendance, fee, quiz, resource, notification, OCR, timetable, section, or report data?
2. If data exists, which Firestore `academy_id` convention was used per collection: admin UID, Firebase UID, or PostgreSQL UUID?
3. Are any Firebase Storage files referenced by `file_url`, and must they remain accessible after migration?
4. Is real-time behavior required for notifications, announcements, sections, timetable, or reports, or is refresh/polling acceptable?
5. Should Firebase be removed completely, or retained temporarily as a read-only archive or file host?
6. Are the legacy `/users` documents the only source of roll numbers, subjects, joining dates, linked children, and security questions?
7. Are `password_recovery` records in use, and how should existing recovery data be handled without exposing answer hashes?
8. What is the retention policy for migrated Firestore source data and the identity ledger?

## 10. Inventory Completion Criteria

This inventory is complete when:

- Every Firestore collection and importing file is accounted for.
- Every Firestore-specific type dependency is known.
- Tenant and identity conventions are documented, including inconsistencies.
- Existing export/migration scripts are classified as unusable or usable.
- Unknown remote-data and real-time decisions are explicit.
- No secret or production credential is recorded in the repository.

Current result: the static inventory is complete, but the remote-data and product-decision items remain open.
