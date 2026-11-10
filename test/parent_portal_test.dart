// Functional tests for the Parent Portal's linked-children flow, driven by
// recorded real API responses (test/fixtures/ui_api_fixtures.json).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:taleemplus_app/features/parent/parent_dashboard.dart';

import 'support/fake_api.dart';

void main() {
  setUpAll(loadRealFonts);

  late Map<String, dynamic> fx;
  late Map<String, dynamic> me;
  late List<Map<String, dynamic>> profiles;
  late List<String> calls;

  setUp(() {
    fx = Map<String, dynamic>.from(loadFixtures()['parent'] as Map);
    me = Map<String, dynamic>.from(fx['GET /auth/me'] as Map);
    profiles = (fx['POST /users/profiles'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    calls = [];
  });

  /// Backend whose parent profile can change between requests (an admin
  /// linking a child from another device).
  Future<http.Response> handle(http.Request req) async {
    {
      final path = req.url.path.split('/api/v2').last;
      calls.add('${req.method} $path');
      if (req.method == 'GET' && path == '/auth/me') {
        return http.Response(jsonEncode({'success': true, 'data': me}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (req.method == 'POST' && path == '/users/profiles') {
        final ids = (jsonDecode(req.body)['ids'] as List).cast<String>();
        final data = profiles.where((p) => ids.contains(p['id'])).toList();
        return http.Response(jsonEncode({'success': true, 'data': data}), 200,
            headers: {'content-type': 'application/json'});
      }
      return fixtureResponse(fx, req);
    }
  }

  MockClient backend() => MockClient(handle);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('dashboard shows the linked child from the API', (tester) async {
    await http.runWithClient(() async {
      final auth = await signedInAuth('parent@demo.taleemplus');
      await tester.pumpWidget(
          await buildApp(tester, home: const ParentDashboard(), auth: auth));
      await settle(tester);
      expect(find.text('Demo Student'), findsWidgets);
      expect(find.text('No children linked yet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, backend);
  });

  testWidgets(
      'pull-to-refresh picks up a child the admin linked after sign-in '
      '(regression: refresh used to be a no-op)', (tester) async {
    // Parent signs in before any child is linked.
    final linked = me['linkedChildren'] as List;
    final child = Map<String, dynamic>.from(linked.first as Map);
    me['linkedChildren'] = <dynamic>[];
    fx['login'] = {
      ...Map<String, dynamic>.from(fx['login'] as Map),
      'user': {
        ...Map<String, dynamic>.from((fx['login'] as Map)['user'] as Map),
        'linkedChildren': <dynamic>[],
      },
    };

    await http.runWithClient(() async {
      final auth = await signedInAuth('parent@demo.taleemplus');
      await tester.pumpWidget(
          await buildApp(tester, home: const ParentDashboard(), auth: auth));
      await settle(tester);
      expect(find.text('No children linked yet'), findsOneWidget);

      // The academy admin links the child on another device.
      me['linkedChildren'] = [child];
      calls.clear();

      await tester.fling(
          find.byType(ListView).first, const Offset(0, 400), 1000);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);

      expect(calls, contains('GET /auth/me'),
          reason: 'Refreshing must re-fetch the parent profile.');
      expect(find.text('Demo Student'), findsWidgets);
      expect(find.text('No children linked yet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, backend);
  });

  testWidgets(
      'a failed profile load shows an error with retry, not "no children"',
      (tester) async {
    var fail = true;
    await http.runWithClient(() async {
      final auth = await signedInAuth('parent@demo.taleemplus');
      await tester.pumpWidget(
          await buildApp(tester, home: const ParentDashboard(), auth: auth));
      await settle(tester);
      expect(find.text('No children linked yet'), findsNothing);
      expect(find.textContaining('Could not load'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text('Demo Student'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, () {
      return MockClient((req) async {
        final path = req.url.path.split('/api/v2').last;
        if (fail && (path == '/auth/me' || path == '/users/profiles')) {
          return http.Response(
              jsonEncode({'success': false, 'message': 'Server unavailable'}),
              503);
        }
        return handle(req);
      });
    });
  });
}
