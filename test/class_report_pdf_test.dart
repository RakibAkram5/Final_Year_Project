import 'package:flutter_test/flutter_test.dart';

import 'package:taleemplus_app/data/models/attendance_record.dart';
import 'package:taleemplus_app/data/models/class_entity.dart';
import 'package:taleemplus_app/data/models/test_mark_model.dart';
import 'package:taleemplus_app/data/remote/class_report_pdf.dart';

void main() {
  final cls = ClassEntity(
    id: 'c1',
    academyId: 'a1',
    className: 'Intermediate Part-II Pre-Engineering',
    section: 'Morning Batch A',
    subject: 'Computer Science',
    studentIds: const ['s1', 's2'],
    studentNames: const {'s1': 'Ayesha Khan', 's2': 'Bilal Ahmed'},
    createdAt: DateTime(2026),
  );

  bool isPdf(List<int> b) =>
      b.length > 500 && String.fromCharCodes(b.take(5)) == '%PDF-';

  AttendanceRecord rec(String student, String status, int day) =>
      AttendanceRecord.fromMap('$student-$day', {
        'academy_id': 'a1',
        'class_id': 'c1',
        'student_id': student,
        'student_name': cls.studentNames[student],
        'log_date': '2026-10-${day.toString().padLeft(2, '0')}',
        'status': status,
      });

  test('attendance PDF for a month', () async {
    final bytes = await ClassReportPdf.attendance(
      academyName: 'Demo Academy',
      cls: cls,
      records: [
        rec('s1', 'present', 1),
        rec('s1', 'late', 2),
        rec('s2', 'absent', 1)
      ],
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 31),
    );
    expect(isPdf(bytes), isTrue);
  });

  test('empty periods still produce a valid document', () async {
    final a = await ClassReportPdf.attendance(
        academyName: 'Demo',
        cls: cls,
        records: const [],
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 1));
    final r = await ClassReportPdf.results(
        academyName: 'Demo', cls: cls, marks: const []);
    expect(isPdf(a) && isPdf(r), isTrue);
  });

  test('large class results paginate without errors', () async {
    final marks = [
      for (var i = 0; i < 200; i++)
        TestMarkModel.fromMap('m$i', {
          'academy_id': 'a1',
          'quiz_id': 'q${i % 4}',
          'student_id': 's$i',
          'student_name': 'Student number $i with a fairly long name',
          'class_id': 'c1',
          'subject': 'Maths',
          'marks_obtained': i % 21,
          'total_marks': 20,
          'percentage': (i % 21) * 5.0,
          'grade_letter': 'B',
        })
    ];
    final bytes = await ClassReportPdf.results(
        academyName: 'Demo',
        cls: cls,
        marks: marks,
        quizTitles: {for (var q = 0; q < 4; q++) 'q$q': 'Unit test $q'});
    expect(isPdf(bytes), isTrue);
  });
}
