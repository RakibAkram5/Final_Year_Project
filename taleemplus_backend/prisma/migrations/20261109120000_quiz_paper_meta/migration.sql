-- Examination-paper layout + teacher answer key for the AI paper generator.
-- Nullable JSONB so existing quizzes and non-exam quizzes are unaffected.
ALTER TABLE "quizzes" ADD COLUMN "paperMeta" JSONB;
