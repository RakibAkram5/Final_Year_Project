import 'package:flutter_test/flutter_test.dart';
import 'package:taleemplus_app/data/remote/api_client.dart';

void main() {
  group('ApiClient date parsing', () {
    test('parses ISO-8601 backend timestamps', () {
      final parsed = ApiClient.parseDate('2026-01-05T10:20:30.000Z');
      expect(parsed, isNotNull);
      expect(parsed!.toUtc(), DateTime.utc(2026, 1, 5, 10, 20, 30));
    });

    test('parses date-only backend values', () {
      expect(ApiClient.parseDate('2026-01-05'), DateTime(2026, 1, 5));
    });

    test('returns null for missing or malformed values', () {
      expect(ApiClient.parseDate(null), isNull);
      expect(ApiClient.parseDate(''), isNull);
      expect(ApiClient.parseDate('not-a-date'), isNull);
    });

    test('uses a fallback or throws for required dates', () {
      final fallback = DateTime(2026, 2, 1);
      expect(ApiClient.parseDateOr(null, fallback), fallback);
      expect(
        () => ApiClient.parseRequiredDate(null, field: 'answered_at'),
        throwsFormatException,
      );
    });

    test('formats date-only payload values without a time component', () {
      expect(ApiClient.dateOnly(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(ApiClient.dateOnly(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('ApiClient enum parsing', () {
    test('normalises uppercase backend enums', () {
      expect(ApiClient.normalizeEnum('PRESENT'), 'present');
      expect(ApiClient.normalizeEnum('PENDING'), 'pending');
      expect(ApiClient.normalizeEnum(null), '');
    });
  });

  group('ApiException', () {
    test('carries the HTTP status and stable error code', () {
      final error = ApiException(
        'Request validation failed.',
        statusCode: 400,
        code: 'VALIDATION_ERROR',
      );

      expect(error.statusCode, 400);
      expect(error.code, 'VALIDATION_ERROR');
      expect(error.toString(), 'Request validation failed.');
    });
  });

  group('Backend attendance fixture', () {
    test('parses the canonical v2 attendance DTO without exceptions', () {
      final fixture = <String, dynamic>{
        'id': '9f1d7a0e-6a55-4c1c-9f1d-7a0e6a55f1d7',
        'academy_id': 'b3f1c0de-7d52-4a4a-9b1e-2c3d4e5f6a7b',
        'class_id': 'c4f1c0de-7d52-4a4a-9b1e-2c3d4e5f6a7b',
        'student_id': 'd5f1c0de-7d52-4a4a-9b1e-2c3d4e5f6a7b',
        'student_name': 'Ayesha Khan',
        'log_date': '2026-01-05',
        'status': 'PRESENT',
        'marked_by_uid': 'e6f1c0de-7d52-4a4a-9b1e-2c3d4e5f6a7b',
        'recorded_at': '2026-01-05T08:30:00.000Z',
      };

      expect(
          ApiClient.parseRequiredDate(fixture['recorded_at'],
              field: 'recorded_at'),
          isA<DateTime>());
      expect(ApiClient.parseDate(fixture['log_date']), DateTime(2026, 1, 5));
      expect(ApiClient.normalizeEnum(fixture['status']), 'present');
      expect(fixture['student_name'], 'Ayesha Khan');
    });
  });
}
