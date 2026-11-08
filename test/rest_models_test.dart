import 'package:flutter_test/flutter_test.dart';
import 'package:taleemplus_app/data/models/attendance_record.dart';
import 'package:taleemplus_app/data/models/class_report_model.dart';
import 'package:taleemplus_app/data/models/class_section.dart';
import 'package:taleemplus_app/data/models/fee_challan_model.dart';
import 'package:taleemplus_app/data/models/quiz_model.dart';
import 'package:taleemplus_app/data/remote/live_query.dart';

/// A challan payload exactly as the v2 backend serializes it.
Map<String, dynamic> challanJson({
  required String dueDate,
  String status = 'pending',
  String billingPeriod = '',
}) =>
    {
      'id': 'c1',
      'academy_id': 'a1',
      'challan_number': 'CH-1',
      'student_id': 's1',
      'student_code': 'code',
      'student_name': 'Ali',
      'father_name': '',
      'billing_period': billingPeriod,
      'class_label': '9 - A',
      'roll_number': '7',
      'issue_date': '2026-11-01T00:00:00.000Z',
      'due_date': dueDate,
      'paid_at': null,
      'monthly_fee': 2500,
      'admission_fee': '0.00', // Prisma Decimal may arrive as a string
      'exam_fee': 0,
      'transport_fee': 0,
      'fine': 100,
      'total_amount': 2600,
      'status': status,
      'created_at': '2026-11-01T08:30:00.000Z',
      'updated_at': '2026-11-02T08:30:00.000Z',
    };

String isoDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).toIso8601String();

void main() {
  group('FeeChallanModel (REST)', () {
    test('keeps ISO dates instead of falling back to now()', () {
      final c = FeeChallanModel.fromMap(
          '', challanJson(dueDate: '2020-01-10T00:00:00.000Z'));
      expect(c.dueDate.toUtc(), DateTime.utc(2020, 1, 10));
      expect(c.issueDate.toUtc(), DateTime.utc(2026, 11, 1));
      expect(c.createdAt.toUtc(), DateTime.utc(2026, 11, 1, 8, 30));
      expect(c.updatedAt.toUtc(), DateTime.utc(2026, 11, 2, 8, 30));
      expect(c.admissionFee, 0);
      expect(c.totalAmount, 2600);
    });

    test('overdue only after the due day has fully passed', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final tomorrow = now.add(const Duration(days: 1));
      final dueToday =
          FeeChallanModel.fromMap('', challanJson(dueDate: isoDay(now)));
      final dueYesterday =
          FeeChallanModel.fromMap('', challanJson(dueDate: isoDay(yesterday)));
      final dueTomorrow =
          FeeChallanModel.fromMap('', challanJson(dueDate: isoDay(tomorrow)));
      expect(dueTomorrow.isOverdue, isFalse);
      expect(dueYesterday.isOverdue, isTrue);
      expect(dueYesterday.effectiveStatus, 'overdue');
      // Paid challans are never overdue.
      final paid = FeeChallanModel.fromMap(
          '', challanJson(dueDate: isoDay(yesterday), status: 'paid'));
      expect(paid.isOverdue, isFalse);
      expect(paid.effectiveStatus, 'paid');
      // A server-flagged overdue status is respected.
      final flagged = FeeChallanModel.fromMap(
          '', challanJson(dueDate: isoDay(tomorrow), status: 'overdue'));
      expect(flagged.isOverdue, isTrue);
      expect(dueToday.isPaid, isFalse);
    });

    test('groups by billing period, not issue date', () {
      final c = FeeChallanModel.fromMap(
          '',
          challanJson(
              dueDate: '2026-12-10T00:00:00.000Z', billingPeriod: '2026-12'));
      expect(c.billingMonth, DateTime(2026, 12));
      final noPeriod = FeeChallanModel.fromMap(
          '', challanJson(dueDate: '2026-10-15T00:00:00.000Z'));
      expect(noPeriod.billingMonth, DateTime(2026, 10));
    });

    test('rejects a challan without a due date instead of inventing one', () {
      final json = challanJson(dueDate: '')..remove('due_date');
      expect(() => FeeChallanModel.fromMap('', json), throwsFormatException);
    });
  });

  group('AttendanceRecord (REST)', () {
    test('parses log_date as a local calendar day', () {
      final r = AttendanceRecord.fromMap('id', {
        'academy_id': 'a',
        'class_id': 'c',
        'student_id': 's',
        'student_name': 'Ali',
        'log_date': '2026-11-08',
        'status': 'LEAVE',
        'marked_by_uid': 't',
        'recorded_at': '2026-11-07T23:30:00.000Z',
      });
      expect(r.logDate, DateTime(2026, 11, 8));
      expect(r.isLeave, isTrue);
      expect(r.recordedAt.toUtc(), DateTime.utc(2026, 11, 7, 23, 30));
    });

    test('rejects records with a missing date', () {
      expect(() => AttendanceRecord.fromMap('id', {'status': 'present'}),
          throwsFormatException);
    });
  });

  group('Quiz and section models (REST)', () {
    test('parses quiz ISO dates and metadata (no Timestamp cast)', () {
      final q = QuizModel.fromMap('q1', {
        'academy_id': 'a',
        'class_id': 'c',
        'class_label': '9 - A',
        'title': 'Unit test',
        'subject': 'Maths',
        'month': 'November',
        'session': '2026',
        'chapter': 'Ch 3',
        'difficulty': 'Hard',
        'total_marks': 20,
        'test_date': '2026-11-20T00:00:00.000Z',
        'created_at': '2026-11-08T10:00:00.000Z',
        'questions': [
          {'id': 'x', 'text': 'Q1', 'type': 'short', 'marks': 3}
        ],
      });
      expect(q.testDate.toUtc(), DateTime.utc(2026, 11, 20));
      expect(q.createdAt!.toUtc(), DateTime.utc(2026, 11, 8, 10));
      expect(q.chapter, 'Ch 3');
      expect(q.questions.single.marks, 3);
    });

    test('parses class sections with roll numbers and ISO dates', () {
      final s = ClassSectionEntity.fromMap('s1', {
        'academy_id': 'a',
        'class_name': 'Matric - Science',
        'program': '',
        'section': 'A',
        'student_ids': ['u1'],
        'student_names': {'u1': 'Ali'},
        'student_roll_numbers': {'u1': null},
        'created_at': '2026-11-08T10:00:00.000Z',
      });
      expect(s.studentIds, ['u1']);
      expect(s.studentRollNumbers, {'u1': ''});
      expect(s.createdAt.toUtc(), DateTime.utc(2026, 11, 8, 10));
      expect(s.displayLabel, 'Matric - Science - A');
    });

    test('parses server-generated class reports', () {
      final r = ClassReportModel.fromMap('r1', {
        'academy_id': 'a',
        'class_label': '9 - A',
        'generated_at': '2026-11-08T10:00:00.000Z',
        'total_students': 3,
        'present': 2,
        'absent': 1,
        'fee_paid': 1,
        'fee_pending': 2,
        'fee_paid_amount': 2500,
        'fee_pending_amount': '5000.50',
      });
      expect(r.feePendingAmount, 5000.5);
      expect(r.generatedAt.toUtc(), DateTime.utc(2026, 11, 8, 10));
    });
  });

  group('liveQuery', () {
    test('re-fetches when its topic changes and ignores other topics',
        () async {
      var calls = 0;
      final values = <int>[];
      final sub =
          liveQuery('test-topic', () async => ++calls).listen(values.add);
      await pumpEventQueue();
      DataChanges.notify('other-topic');
      await pumpEventQueue();
      DataChanges.notify('test-topic');
      await pumpEventQueue();
      expect(values, [1, 2]);
      await sub.cancel();
    });

    test('emits errors as errors and keeps running', () async {
      var fail = true;
      final values = <String>[];
      final errors = <Object>[];
      final sub = liveQuery('err-topic', () async {
        if (fail) throw StateError('offline');
        return 'ok';
      }).listen(values.add, onError: errors.add);
      await pumpEventQueue();
      expect(errors.single, isA<StateError>());
      expect(values, isEmpty);
      fail = false;
      DataChanges.notify('err-topic');
      await pumpEventQueue();
      expect(values, ['ok']);
      await sub.cancel();
    });
  });
}
