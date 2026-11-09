import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taleemplus_app/core/theme/app_theme.dart';
import 'package:taleemplus_app/logic/academic_structure_provider.dart';
import 'package:taleemplus_app/logic/admin_ai_provider.dart';
import 'package:taleemplus_app/logic/attendance_provider.dart';
import 'package:taleemplus_app/logic/auth_provider.dart';
import 'package:taleemplus_app/logic/class_provider.dart';
import 'package:taleemplus_app/logic/class_section_provider.dart';
import 'package:taleemplus_app/logic/member_provider.dart';
import 'package:taleemplus_app/logic/parent_provider.dart';
import 'package:taleemplus_app/logic/quiz_provider.dart';
import 'package:taleemplus_app/logic/session_provider.dart';
import 'package:taleemplus_app/logic/theme_provider.dart';
import 'package:taleemplus_app/logic/timetable_provider.dart';

/// Font files from the Flutter SDK, found case-insensitively (file names
/// differ in case between platforms). Null when they are not available.
Map<String, String>? _sdkFontFiles() {
  // Lets CI-like runs without SDK fonts be reproduced locally.
  if (Platform.environment['TEST_WITHOUT_REAL_FONTS'] == '1') return null;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return null;
  final files = <String, String>{
    for (final e in dir.listSync().whereType<File>())
      e.uri.pathSegments.last.toLowerCase(): e.path,
  };
  final required = ['roboto-regular.ttf', 'materialicons-regular.otf'];
  return required.every(files.containsKey) ? files : null;
}

/// Whether [loadRealFonts] can load the real fonts. Layout tests are skipped
/// without them: the default test font renders every glyph as a full-em
/// square, so measurements would report false overflows.
bool get realFontsAvailable => _sdkFontFiles() != null;

/// Loads the real Roboto and Material Icons fonts from the Flutter SDK.
///
/// flutter_test otherwise renders every glyph as a full-em square, which
/// makes text roughly twice as wide as on a phone and produces false
/// overflow reports. Returns false if the SDK fonts cannot be found.
Future<bool> loadRealFonts() async {
  final files = _sdkFontFiles();
  if (files == null) return false;
  Future<void> load(String family, List<String> names) async {
    final loader = FontLoader(family);
    for (final name in names) {
      final path = files[name];
      if (path == null) continue;
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
    'roboto-light.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
  return true;
}

/// Real API responses recorded from a local seeded backend by
/// `tool/record_ui_fixtures.js`.
Map<String, dynamic> loadFixtures() =>
    jsonDecode(File('test/fixtures/ui_api_fixtures.json').readAsStringSync())
        as Map<String, dynamic>;

final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// A mock backend answering with the recorded responses for [role].
MockClient fakeBackend(Map<String, dynamic> roleFixtures) =>
    MockClient((request) async => fixtureResponse(roleFixtures, request));

/// The recorded response for [request] (used directly by tests that
/// override a few endpoints).
http.Response fixtureResponse(
    Map<String, dynamic> roleFixtures, http.BaseRequest request) {
  {
    final full = request.url.path;
    final idx = full.indexOf('/api/v2');
    final path = idx >= 0 ? full.substring(idx + 7) : full;
    final method = request.method;
    if (method == 'POST' && path == '/auth/login') {
      return _ok(roleFixtures['login']);
    }
    final generic =
        path.split('/').map((s) => _uuid.hasMatch(s) ? ':id' : s).join('/');
    final category = request.url.queryParameters['category'];
    for (final key in [
      if (category != null) '$method $path#$category',
      '$method $path',
      '$method $generic',
    ]) {
      if (roleFixtures.containsKey(key)) return _ok(roleFixtures[key]);
    }
    if (method == 'GET') return _ok(<dynamic>[]);
    return _ok(<String, dynamic>{});
  }
}

http.Response _ok(dynamic data) => http.Response(
      jsonEncode({'success': true, 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Device sizes required by the responsive test plan (logical pixels).
const testViewports = <String, Size>{
  'small-android-320x568': Size(320, 568),
  'android-360x800': Size(360, 800),
  'android-390x844': Size(390, 844),
  'large-android-412x915': Size(412, 915),
  'tablet-portrait-768x1024': Size(768, 1024),
  'tablet-landscape-1024x768': Size(1024, 768),
  'laptop-1366x768': Size(1366, 768),
  'desktop-1920x1080': Size(1920, 1080),
  'large-desktop-2560x1440': Size(2560, 1440),
};

/// Signs in through the mocked API and returns the app's provider tree around
/// [home], exactly as `main.dart` wires it.
Future<Widget> buildApp(
  WidgetTester tester, {
  required Widget home,
  required AuthProvider auth,
  ThemeMode themeMode = ThemeMode.dark,
}) async {
  final theme = ThemeProvider();
  await theme.setThemeMode(themeMode);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider(create: (_) => MemberProvider()),
      ChangeNotifierProvider(create: (_) => ClassProvider()),
      ChangeNotifierProvider(create: (_) => ClassSectionProvider()),
      ChangeNotifierProvider(create: (_) => AttendanceProvider()),
      ChangeNotifierProvider(create: (_) => QuizProvider()),
      ChangeNotifierProvider(create: (_) => TimetableProvider()),
      ChangeNotifierProvider(create: (_) => AdminAiProvider()),
      ChangeNotifierProvider(create: (_) => AcademicStructureProvider()),
      ChangeNotifierProxyProvider<AuthProvider, ParentProvider>(
        create: (_) => ParentProvider(),
        update: (_, a, p) => p!..syncWithUser(a.currentUser),
      ),
      ChangeNotifierProxyProvider<AuthProvider, SessionProvider>(
        create: (_) => SessionProvider(),
        update: (_, a, s) => s!..updateAuth(a),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: home,
    ),
  );
}

Future<AuthProvider> signedInAuth(String email) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthProvider();
  final ok = await auth.signIn(email: email, password: 'x');
  if (!ok) throw StateError('Mock sign-in failed: ${auth.errorMessage}');
  return auth;
}
