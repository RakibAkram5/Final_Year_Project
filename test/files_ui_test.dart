// Functional widget tests for file/assignment screens using recorded real
// API responses (test/fixtures/ui_api_fixtures.json).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:taleemplus_app/data/models/class_entity.dart';
import 'package:taleemplus_app/data/remote/assignment_service.dart';
import 'package:taleemplus_app/data/remote/file_service.dart';
import 'package:taleemplus_app/features/shared/assignments_screen.dart';
import 'package:taleemplus_app/features/shared/course_materials_view.dart';
import 'package:taleemplus_app/features/shared/documents_screen.dart';
import 'package:taleemplus_app/features/shared/file_viewer_screen.dart';

import 'support/fake_api.dart';

void main() {
  setUpAll(loadRealFonts);
  final all = loadFixtures();
  Map<String, dynamic> fx(String role) =>
      Map<String, dynamic>.from(all[role] as Map);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> run(WidgetTester tester, String role, Widget home,
      Future<void> Function() body,
      {MockClient? client}) async {
    final f = fx(role);
    await http.runWithClient(() async {
      final auth = await signedInAuth('$role@demo.taleemplus');
      await tester.pumpWidget(await buildApp(tester, home: home, auth: auth));
      await settle(tester);
      await body();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, () => client ?? fakeBackend(f));
  }

  testWidgets('student sees assignment with submitted status', (tester) async {
    await run(tester, 'student', const AssignmentsScreen(), () async {
      expect(find.textContaining('Fractions worksheet'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('New assignment'), findsNothing); // staff only
    });
  });

  testWidgets('teacher sees submission count and can create', (tester) async {
    await run(tester, 'teacher', const AssignmentsScreen(), () async {
      expect(find.text('1 submitted'), findsOneWidget);
      expect(find.text('New assignment'), findsOneWidget);
    });
  });

  testWidgets('student assignment detail lists brief and own submission files',
      (tester) async {
    final a = Assignment.fromJson(Map<String, dynamic>.from(
        (fx('student')['GET /assignments'] as List).first as Map));
    final me = (fx('student')['GET /auth/me'] as Map)['id'] as String;
    await run(tester, 'student',
        AssignmentDetailScreen(assignment: a, staff: false, studentId: me),
        () async {
      expect(find.textContaining('Fractions worksheet (unlike denominators)'),
          findsOneWidget);
      expect(find.text('my-answers.pdf'), findsOneWidget);
      expect(find.text('Save note'), findsOneWidget);
    });
  });

  testWidgets('teacher assignment detail lists submissions to grade',
      (tester) async {
    final a = Assignment.fromJson(Map<String, dynamic>.from(
        (fx('teacher')['GET /assignments'] as List).first as Map));
    await run(tester, 'teacher',
        AssignmentDetailScreen(assignment: a, staff: true, studentId: ''),
        () async {
      expect(find.textContaining('SUBMISSIONS (1 of'), findsOneWidget);
      expect(find.text('Demo Student'), findsOneWidget);
      expect(find.text('Grade'), findsOneWidget);
    });
  });

  testWidgets('course materials show attached files; students cannot upload',
      (tester) async {
    final cls = ClassEntity.fromMap(
        '',
        Map<String, dynamic>.from((fx('student')['GET /classes'] as List)
            .firstWhere((c) => c['class_name'] == 'Grade 5') as Map));
    await run(tester, 'student',
        Scaffold(body: CourseMaterialsView(classEntity: cls)), () async {
      expect(find.text('Fractions notes'), findsOneWidget);
      expect(find.text('Fractions notes chapter 3.pdf'), findsOneWidget);
      expect(find.text('Upload'), findsNothing);
      expect(find.text('Share material'), findsNothing);
    });
  });

  testWidgets('parent sees child documents read-only', (tester) async {
    final childId =
        ((fx('parent')['GET /auth/me'] as Map)['linkedChildren'] as List)
            .first['id'] as String;
    await run(
        tester,
        'parent',
        DocumentsScreen(
            title: 'Documents',
            category: FileCategory.studentDocument,
            ownerId: childId), () async {
      expect(find.text('Admission form 2026.pdf'), findsOneWidget);
      expect(find.text('Upload'), findsNothing);
    });
  });

  group('file viewer', () {
    final png = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
    StoredFile file(String mime, String name) => StoredFile(
        id: '11111111-1111-4111-8111-111111111111',
        category: 'STUDENT_DOCUMENT',
        ownerId: 'x',
        originalName: name,
        mimeType: mime,
        sizeBytes: 70,
        createdAt: DateTime(2026, 11, 9));

    MockClient bytes(int status, List<int> body) => MockClient((req) async {
          if (req.url.path.endsWith('/content')) {
            return http.Response.bytes(body, status,
                headers: {'content-type': 'application/json'});
          }
          return fixtureResponse(fx('student'), req);
        });

    testWidgets('previews an image', (tester) async {
      await run(tester, 'student',
          FileViewerScreen(file: file('image/png', 'scan.png')), () async {
        expect(find.byType(InteractiveViewer), findsOneWidget);
      }, client: bytes(200, png));
    });

    testWidgets('offers download for formats without preview', (tester) async {
      await run(
          tester,
          'student',
          FileViewerScreen(
              file: file(
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                  'essay.docx')), () async {
        expect(find.textContaining('Preview is not available'), findsOneWidget);
        expect(find.text('Download / share'), findsOneWidget);
      }, client: bytes(200, [80, 75, 3, 4]));
    });

    testWidgets('shows an error with retry when the file is gone',
        (tester) async {
      await run(tester, 'student',
          FileViewerScreen(file: file('application/pdf', 'old.pdf')), () async {
        expect(find.textContaining('Could not load this file'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      },
          client: bytes(
              404,
              utf8.encode(jsonEncode(
                  {'success': false, 'message': 'File not found.'}))));
    });
  });
}
