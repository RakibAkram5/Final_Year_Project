import 'package:flutter_test/flutter_test.dart';
import 'package:taleemplus_app/core/constants/app_constants.dart';
import 'package:taleemplus_app/data/models/app_user.dart';
import 'package:taleemplus_app/data/remote/pdf_generator_service.dart';
import 'package:taleemplus_app/logic/exam_paper_generator.dart';

/// Builds a real multi-section Computer Science paper and renders both the
/// student paper and the teacher answer key to PDF bytes, asserting the whole
/// pipeline (generate -> sections -> PDF layout -> save) runs without throwing
/// and produces valid, non-trivial PDF documents. A layout overflow or broken
/// table in the `pdf` package surfaces as an exception at save(), so a clean
/// render is a meaningful end-to-end check.
void main() {
  // Required so rootBundle can load the bundled PDF font asset in tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  const academy = AppUser(
    uid: 'teacher-1',
    fullName: 'Test Teacher',
    email: 'teacher@example.com',
    phoneNumber: '0300-0000000',
    role: UserRole.teacher,
    academyName: 'Sunrise Science Academy',
    academyId: 'acad-1',
    academyAddress: 'Main Road, Lahore',
    academyPhone: '042-111-2222',
    // No academyLogo: avoids any network image fetch during the test.
  );

  bool isPdf(List<int> bytes) =>
      bytes.length > 1000 &&
      bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46; // F

  test('renders a multi-section CS paper and answer key to valid PDFs',
      () async {
    final result = ExamPaperGenerator().generate(
      const ExamConfig(
        title: 'First Monthly Test',
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
      ),
      academyId: 'acad-1',
      classId: 'class-1',
      createdByUid: 'teacher-1',
      createdByName: 'Test Teacher',
    );
    expect(result.ok, isTrue, reason: result.error);
    final quiz = result.quiz!;

    final paper = await PdfGeneratorService.renderStudentPaper(quiz, academy);
    final key = await PdfGeneratorService.renderAnswerKey(quiz, academy);

    expect(isPdf(paper), isTrue, reason: 'student paper is not a valid PDF');
    expect(isPdf(key), isTrue, reason: 'answer key is not a valid PDF');
  });

  test('renders a legacy quiz (no sections) via the type-grouping fallback',
      () async {
    // Simulate a quiz loaded from history without paperMeta sections.
    final legacy = ExamPaperGenerator()
        .generate(
          const ExamConfig(
            title: 'Legacy',
            subject: 'Mathematics',
            classLabel: '9th',
            mcqCount: 4,
            shortGroups: [
              ShortGroupConfig(partsCount: 3, attemptCount: 3, marksPerPart: 2),
            ],
            longCount: 1,
            longAttempt: 1,
            marksPerLong: 8,
          ),
          academyId: 'acad-1',
          classId: 'class-1',
          createdByUid: 't',
          createdByName: 'T',
        )
        .quiz!
        .copyWith(sections: const []); // drop sections -> fallback path

    final paper = await PdfGeneratorService.renderStudentPaper(legacy, academy);
    expect(isPdf(paper), isTrue);
  });
}
