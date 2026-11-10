import 'package:flutter_test/flutter_test.dart';
import 'package:taleemplus_app/data/models/quiz_model.dart';
import 'package:taleemplus_app/logic/exam_paper_generator.dart';

void main() {
  final gen = ExamPaperGenerator();

  GenerationResult build(ExamConfig config) => gen.generate(
        config,
        academyId: 'acad-1',
        classId: 'class-1',
        createdByUid: 'teacher-1',
        createdByName: 'Test Teacher',
      );

  group('ExamPaperGenerator', () {
    test('Computer Science paper with 20 MCQs and correct marks total', () {
      const config = ExamConfig(
        title: 'CS Monthly Test',
        subject: 'Computer Science',
        classLabel: '9th (A)',
        examType: 'Monthly Test',
        timeAllowed: '2 hours',
        mcqCount: 20,
        marksPerMcq: 1,
        shortGroups: [
          ShortGroupConfig(partsCount: 6, attemptCount: 4, marksPerPart: 2),
          ShortGroupConfig(partsCount: 6, attemptCount: 4, marksPerPart: 2),
        ],
        longCount: 3,
        longAttempt: 2,
        marksPerLong: 8,
      );
      final result = build(config);

      expect(result.ok, isTrue, reason: result.error);
      final quiz = result.quiz!;

      // Section A has exactly 20 MCQs.
      final mcqSection =
          quiz.sections.firstWhere((s) => s.kind == SectionKind.mcq);
      expect(mcqSection.questionIds.length, 20);

      // Two short groups + one long section.
      expect(quiz.sections.where((s) => s.kind == SectionKind.short).length, 2);
      expect(quiz.sections.where((s) => s.kind == SectionKind.long).length, 1);

      // Marks: 20*1 + 2 groups*(4*2) + (2*8) = 20 + 16 + 16 = 52.
      expect(quiz.computedTotalMarks, 52);
      expect(result.marks!.total, 52);
    });

    test('questions never repeat within a paper', () {
      const config = ExamConfig(
        title: 'CS',
        subject: 'Computer Science',
        classLabel: '9th',
        mcqCount: 22,
        shortGroups: [
          ShortGroupConfig(partsCount: 6, attemptCount: 4, marksPerPart: 2),
        ],
        longCount: 3,
        longAttempt: 2,
        marksPerLong: 8,
      );
      final quiz = build(config).quiz!;
      final texts = quiz.questions.map((q) => q.text.toLowerCase()).toList();
      expect(texts.toSet().length, texts.length,
          reason: 'duplicate question text found');
    });

    test('Mathematics and English papers generate from the bank', () {
      for (final subject in ['Mathematics', 'English']) {
        final result = build(ExamConfig(
          title: '$subject Test',
          subject: subject,
          classLabel: '9th',
          mcqCount: 5,
          shortGroups: const [
            ShortGroupConfig(partsCount: 4, attemptCount: 3, marksPerPart: 2),
          ],
          longCount: 2,
          longAttempt: 1,
          marksPerLong: 8,
        ));
        expect(result.ok, isTrue, reason: '$subject: ${result.error}');
        expect(result.quiz!.questions, isNotEmpty);
      }
    });

    test('unknown subject with no source material fails loudly', () {
      const config = ExamConfig(
        title: 'Mystery',
        subject: 'Astrophysics',
        classLabel: '9th',
        mcqCount: 5,
      );
      final result = build(config);
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('source material produces questions for an unsupported subject', () {
      const source =
          'Photosynthesis is the process by which green plants make food. '
          'Chlorophyll is the green pigment that absorbs sunlight. '
          'The stomata are tiny pores that allow gas exchange in leaves. '
          'Respiration releases energy stored in glucose for the cell to use.';
      final result = build(const ExamConfig(
        title: 'Biology',
        subject: 'Biology',
        classLabel: '9th',
        mcqCount: 1,
        shortGroups: [
          ShortGroupConfig(partsCount: 2, attemptCount: 2, marksPerPart: 2),
        ],
        longCount: 1,
        longAttempt: 1,
        marksPerLong: 8,
        sourceText: source,
      ));
      expect(result.ok, isTrue, reason: result.error);
      expect(result.quiz!.questions, isNotEmpty);
    });

    test('marks validation flags a mismatched target', () {
      const config = ExamConfig(
        title: 'x',
        subject: 'Computer Science',
        classLabel: '9th',
        mcqCount: 10,
        marksPerMcq: 1,
        shortGroups: [
          ShortGroupConfig(partsCount: 6, attemptCount: 4, marksPerPart: 2),
        ],
        longCount: 3,
        longAttempt: 2,
        marksPerLong: 8,
      );
      // Actual = 10 + 8 + 16 = 34. Target 20 (the reference PDF's bad number).
      final breakdown = gen.validateMarks(config, target: 20);
      expect(breakdown.total, 34);
      expect(breakdown.mismatch, isTrue);

      final ok = gen.validateMarks(config, target: 34);
      expect(ok.mismatch, isFalse);
    });
  });

  group('paperMeta round-trip', () {
    test('sections, exam metadata and answers survive serialization', () {
      final quiz = build(const ExamConfig(
        title: 'CS Final',
        subject: 'Computer Science',
        classLabel: '9th (A)',
        examType: 'Final Term',
        timeAllowed: '3 hours',
        chapters: ['Computer Architecture'],
        mcqCount: 3,
        shortGroups: [
          ShortGroupConfig(partsCount: 2, attemptCount: 2, marksPerPart: 2),
        ],
        longCount: 1,
        longAttempt: 1,
        marksPerLong: 8,
      )).quiz!;

      // Serialize to the API map and rebuild (simulates save + reopen).
      final map = quiz.toMap();
      final restored = QuizModel.fromMap(quiz.id, map);

      expect(restored.examType, 'Final Term');
      expect(restored.timeAllowed, '3 hours');
      expect(restored.sections.length, quiz.sections.length);
      expect(restored.computedTotalMarks, quiz.computedTotalMarks);

      // Teacher model answers are restored onto the questions.
      final withAnswers =
          restored.questions.where((q) => (q.answerText ?? '').isNotEmpty);
      expect(withAnswers, isNotEmpty);
    });
  });
}
