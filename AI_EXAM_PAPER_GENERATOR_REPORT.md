# Implementation Report — Professional Exam-Paper Generator

**Feature:** Professional Pakistani examination-paper format for the TaleemPlus
AI Test Generator (web + Flutter Android, shared codebase).
**Date:** 2026-11-09
**Status:** Implemented and verified by automated tests (`flutter analyze` clean,
`flutter test` 123 passing, backend Jest unit tests passing).

---

## 1. Approach & key facts

- The **web app and the Android app are one Flutter codebase** (`lib/`). The web
  build is Flutter web, so the feature was implemented once in Flutter and serves
  both, with no duplication.
- The existing PDF stack (`pdf` + `printing`) works on web and Android and was
  reused. The generation logic lives in one shared service — **no duplicate
  generators** were created.
- Decisions (confirmed with the user): **hybrid** engine (offline default +
  optional LLM), **build layout from the written spec** (the reference PDF was not
  in the workspace), and **English now with Urdu-ready structure**.

## 2. Files created

| File | Purpose |
|---|---|
| `lib/logic/exam_paper_generator.dart` | Hybrid generation engine: `ExamConfig`, `ExamPaperGenerator`, `MarksBreakdown`, section assembly, dedup, marks validation. |
| `lib/data/exam/curriculum_bank.dart` | Vetted offline question bank for Computer Science (22 MCQ / 14 short / 4 long), Mathematics and English, each item with a model answer. |
| `lib/features/quiz/screens/exam_paper_generator_screen.dart` | The professional generator UI: dynamic config, live marks summary/validation, source-material (paste + OCR), preview, print, download paper, download answer key, save to history, optional AI toggle. |
| `taleemplus_backend/src/services/aiQuestionService.js` | Optional, guarded LLM path (OpenAI-compatible / Vercel AI Gateway). Disabled without a key. |
| `taleemplus_backend/prisma/migrations/20261109120000_quiz_paper_meta/migration.sql` | Adds the `paperMeta` JSONB column. |
| `taleemplus_backend/tests/aiQuestionService.test.js` | Unit tests for the AI service (not-configured path, sanitizer, JSON parsing). |
| `test/exam_paper_generator_test.dart` | Generator unit tests (counts, marks, dedup, fallbacks, round-trip). |
| `test/exam_paper_pdf_test.dart` | Renders student paper + answer key to valid PDFs end-to-end. |
| `assets/fonts/NotoSans-{Regular,Bold,Italic}.ttf` | Bundled Unicode font for clean PDF typography. |

## 3. Files modified

| File | Change |
|---|---|
| `lib/data/models/quiz_model.dart` | Additive: `PaperSection`/`SectionKind`, `QuizQuestion.answerText`, exam fields (`examType`, `timeAllowed`, `language`, `chapters`, `sections`), `paperMeta` (de)serialization with answer/section backfill, `computedTotalMarks`. Legacy quizzes unaffected. |
| `lib/data/remote/pdf_generator_service.dart` | Rewritten: professional student paper (header, MCQ table, roman-numbered short groups, Part II) + separate teacher answer key, A4, page numbers, footer, bundled font, legacy fallback. |
| `lib/data/remote/quiz_service.dart` | Sends `paperMeta` on create; `aiGenerateItems()` (graceful fallback). |
| `lib/widgets/app_widgets.dart` | `LabeledField` gained an optional `onChanged` (for the live marks summary). |
| `lib/features/quiz/screens/teacher_quiz_list_screen.dart` | AI FAB/button now opens the new generator screen. |
| `taleemplus_backend/prisma/schema.prisma` | `Quiz.paperMeta Json?`. |
| `taleemplus_backend/src/controllers/quizController.js` | Round-trips `paperMeta`, **strips the answer key for students**, `aiGenerate` endpoint. |
| `taleemplus_backend/src/routes/quizRoutes.js` | `POST /quizzes/ai-generate`. |
| `taleemplus_backend/.env.example`, `pubspec.yaml`, `CHANGELOG.md` | AI env docs, font asset, changelog. |

## 4. Features implemented (against the spec)

- **Header** — academy name/address/phone + logo, exam title, subject, class,
  student/roll/section blanks, time allowed, total marks, chapters, date,
  signature line. All dynamic.
- **Section A MCQs** — `No. | Question | A | B | C | D` table, four options each,
  one correct answer stored for the key, wrapping, per-section marks line.
- **Short questions** — multiple groups, roman numerals `(i)(ii)…`, "attempt any
  N (m×N=T Marks)", automatic marks.
- **Part II long questions** — continuous numbering, "attempt any N", configurable
  marks.
- **Professional PDF** — A4, margins, bold headings, aligned tables, page breaks,
  running header, page numbers, "Generated with TaleemPlus" footer, bundled
  Unicode font (no missing glyphs).
- **Dynamic configuration** — subject, class, chapters, exam type, total marks,
  time, MCQ/short/long counts, marks per question, attempt-any counts, difficulty
  (Easy/Medium/Hard/Mixed), language (English; Urdu structure in place).
- **Marks validation** — the paper always prints the **computed** total; an
  optional "expected total" field flags any mismatch. This is the explicit fix for
  the reference PDF's 20-vs-42 inconsistency.
- **AI quality** — generates from selected chapters/difficulty, avoids repeats,
  Pakistani terminology, real MCQ distractors, uses uploaded/scanned material when
  present, and **tells the teacher instead of inventing** when no vetted bank and no
  source/AI exist for a subject.
- **Teacher answer key** — separate PDF with MCQ answers (highlighted + letter
  column), short/long model answers and marking guidelines. The student paper and
  the student API response never contain answers.
- **Export/printing/history** — download PDF, print, download key separately,
  in-app preview (paper and key), save to examination history, reopen (layout +
  key restored from `paperMeta`).
- **Branding** — academy name + "Generated with TaleemPlus"; no third-party
  developer credit.
- **Isolation/permissions** — reuses existing auth, academy scoping and
  teacher/admin role checks; the AI endpoint is `ADMIN`/`TEACHER` only.

## 5. Tests performed (automated)

- **Flutter:** `flutter analyze lib test` → no issues. `flutter test` → **123
  passing** (incl. all pre-existing).
  - Generator: CS paper with **20 MCQs** and correct total (52); **no repeated
    questions**; Mathematics and English papers generate; unknown subject with no
    source **fails loudly**; source material drives an unsupported subject; marks
    mismatch flagged; `paperMeta` round-trips (sections, metadata, answers).
  - PDF: a **multi-section** CS paper **and** the answer key render to valid,
    multi-page PDFs with **no missing-glyph warnings**; the legacy (no-sections)
    fallback also renders.
- **Backend (Jest):** AI service disabled without a key, enabled with one; malformed
  items dropped; out-of-range `correctIndex` clamped; fenced-JSON parsed;
  unparseable content → empty. Prisma schema validates; controller/routes load.

## 6. Bugs fixed / defects avoided

- **Reference total-marks inconsistency** (header 20 vs sections 42) — the generator
  computes and prints the real total and surfaces a mismatch warning.
- **Difficulty filter starvation** — an early version hard-filtered by difficulty
  and could not fill a 20-MCQ paper; difficulty is now a soft ordering preference,
  never dropping questions.
- **Missing PDF glyphs** — the built-in Helvetica silently dropped `—`, `√`, etc.;
  fixed by bundling Noto Sans and setting the PDF theme, plus rewording a few
  out-of-coverage symbols in the bank.
- **Answer-key leakage** — model answers (in `paperMeta`) are stripped for
  non-teacher/admin callers at the API layer.

## 7. Known limitations / follow-ups

- **Urdu rendering**: the `language` field, selection and code paths are in place,
  but the Urdu (Nastaliq) font is not yet bundled, so Urdu glyphs will not display
  correctly in the PDF until that font is added to the theme's `fontFallback`
  (deferred per the agreed scope).
- **`paperMeta` migration**: cross-session persistence of the exact layout and the
  answer key requires `prisma migrate deploy` to apply
  `20261109120000_quiz_paper_meta`. Until then, generation/preview/print/download
  all work; a reopened paper falls back to type-grouped sections (still a valid
  professional paper) and short/long model answers are not re-loaded.
- **Optional LLM path**: returns `501` (→ offline) unless `AI_API_KEY` is set. The
  sanitizer/parser are unit-tested; the live provider call itself was not exercised
  here (no key).
- **Curriculum bank**: ships vetted content for Computer Science, Mathematics and
  English. Other subjects need scanned/pasted source material or the AI path; the
  generator tells the teacher rather than fabricating.
- **Manual verification**: validated via automated tests, PDF byte rendering and
  static analysis; not run in a device/emulator or browser in this session.
- The previous OCR-notes `CreateQuizScreen` is now superseded by the new generator
  and left in place (unused) to avoid touching unrelated flows.
