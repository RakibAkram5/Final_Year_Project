// Academy location (Phase 6) and payment details (Phase 8) as seen by
// students/parents, using recorded real API responses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:taleemplus_app/features/parent/screens/student_challan_screen.dart';
import 'package:taleemplus_app/features/shared/academy_location.dart';

import 'support/fake_api.dart';

void main() {
  setUpAll(loadRealFonts);
  final all = loadFixtures();

  Future<void> run(WidgetTester tester, String role, Widget home,
      Future<void> Function() body) async {
    final fx = Map<String, dynamic>.from(all[role] as Map);
    await http.runWithClient(() async {
      final auth = await signedInAuth('$role@demo.taleemplus');
      await tester.pumpWidget(await buildApp(tester, home: home, auth: auth));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await body();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, () => fakeBackend(fx));
  }

  testWidgets('student sees saved academy location with directions',
      (tester) async {
    await run(tester, 'student', const AcademyLocationScreen(), () async {
      expect(find.textContaining('12-B Main Boulevard'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Open map'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    });
  });

  testWidgets('parent sees bank details and IBAN when paying a challan',
      (tester) async {
    final childId = ((all['parent'] as Map)['GET /auth/me']
        as Map)['linkedChildren'][0]['id'] as String;
    await run(tester, 'parent', StudentChallanScreen(studentUid: childId),
        () async {
      await tester.ensureVisible(find.text('PAY NOW').first);
      await tester.tap(find.text('PAY NOW').first);
      await tester.pumpAndSettle();
      expect(find.text('PK36SCBL0000001123456702'), findsOneWidget);
      expect(find.text('[TEST] Demo Bank'), findsOneWidget);
      expect(find.textContaining('only after academy verification'),
          findsOneWidget);
    });
    // The full payment sheet only fits with real font metrics.
  }, skip: !realFontsAvailable);
}
