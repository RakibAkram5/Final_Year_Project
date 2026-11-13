-- Online quiz attempts (student portal). Additive only: existing quizzes
-- default to attemptMode = PAPER and keep behaving exactly as before.
-- quiz_submissions: one row per (quiz, student) -> safe submit retries.
-- quiz_answers: one row per (submission, question).
-- AlterTable
ALTER TABLE "quizzes" ADD COLUMN     "attemptMode" TEXT NOT NULL DEFAULT 'PAPER',
ADD COLUMN     "availableFrom" TIMESTAMP(3),
ADD COLUMN     "availableUntil" TIMESTAMP(3),
ADD COLUMN     "durationMinutes" INTEGER;

-- CreateTable
CREATE TABLE "quiz_submissions" (
    "id" TEXT NOT NULL,
    "academyId" TEXT NOT NULL,
    "quizId" TEXT NOT NULL,
    "studentId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'IN_PROGRESS',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "submittedAt" TIMESTAMP(3),
    "gradedAt" TIMESTAMP(3),
    "autoScore" DOUBLE PRECISION,
    "autoMaxScore" DOUBLE PRECISION,
    "finalScore" DOUBLE PRECISION,
    "needsReview" BOOLEAN NOT NULL DEFAULT false,
    "teacherNote" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "quiz_submissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quiz_answers" (
    "id" TEXT NOT NULL,
    "submissionId" TEXT NOT NULL,
    "questionId" TEXT NOT NULL,
    "selectedIndex" INTEGER,
    "answerText" TEXT,
    "isCorrect" BOOLEAN,
    "marksAwarded" DOUBLE PRECISION,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "quiz_answers_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "quiz_submissions_academyId_quizId_status_idx" ON "quiz_submissions"("academyId", "quizId", "status");

-- CreateIndex
CREATE INDEX "quiz_submissions_studentId_submittedAt_idx" ON "quiz_submissions"("studentId", "submittedAt");

-- CreateIndex
CREATE UNIQUE INDEX "quiz_submissions_quizId_studentId_key" ON "quiz_submissions"("quizId", "studentId");

-- CreateIndex
CREATE UNIQUE INDEX "quiz_answers_submissionId_questionId_key" ON "quiz_answers"("submissionId", "questionId");

-- AddForeignKey
ALTER TABLE "quiz_submissions" ADD CONSTRAINT "quiz_submissions_academyId_fkey" FOREIGN KEY ("academyId") REFERENCES "academies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quiz_submissions" ADD CONSTRAINT "quiz_submissions_quizId_fkey" FOREIGN KEY ("quizId") REFERENCES "quizzes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quiz_submissions" ADD CONSTRAINT "quiz_submissions_studentId_fkey" FOREIGN KEY ("studentId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quiz_answers" ADD CONSTRAINT "quiz_answers_submissionId_fkey" FOREIGN KEY ("submissionId") REFERENCES "quiz_submissions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quiz_answers" ADD CONSTRAINT "quiz_answers_questionId_fkey" FOREIGN KEY ("questionId") REFERENCES "quiz_questions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

