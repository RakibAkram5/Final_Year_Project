# TaleemPlus Android Release Startup Performance Audit

**Audit type:** Read-only cold-start performance audit  
**Platform:** Flutter Android release APK  
**Target device:** Physical Android phone  
**Date:** 2026-11-07  
**Branch/working tree:** `fix/ci-pipeline` (current uncommitted working tree)

## Scope and method

This audit inspected the current working tree without modifying source code, schema, migrations, Firebase packages, or existing uncommitted changes.

Evidence sources:

- `lib/main.dart`, splash/auth flow, providers, API client, Firebase options
- Android manifest, merged release manifest, Gradle configuration, launch themes
- Existing release APK metadata and manifest-merger output under `build/`
- Asset dimensions and byte sizes
- `pubspec.yaml` / `pubspec.lock`
- Flutter network-policy documentation for Android cleartext behavior: `https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android`

A physical device was not attached during this audit (`adb devices` returned no devices), so the report contains **static code and build-artifact evidence**, not measured launch traces. The final section describes the on-device measurement plan needed to confirm exact millisecond costs.

---

## Executive summary

The dominant cold-start cost is **not** Flutter engine startup. It is the splash/auth sequence:

1. `Firebase.initializeApp()` is awaited **before** `runApp()`.
2. The first Flutter frame appears.
3. The splash screen awaits a **remote `/auth/me` call** if an access token exists.
4. After that call completes, it waits an **additional fixed 2,500 ms**.
5. Only then does it navigate to the dashboard or login.

Because the 2.5-second delay is **after** the awaited network call, the delay is **additive**, not a minimum:

- No stored session: **at least ~2.5 s** after the first frame.
- Stored session, backend reachable: **~2.5 s + auth round trip**.
- Stored session, backend unreachable: **~2.5 s + up to 20 s** (`ApiClient` timeout), i.e. potentially **~22.5 s** before login.

The release configuration also points Android at a hardcoded private LAN URL (`http://192.168.10.9:5000/api/v2`) and the release workflows do not inject `API_BASE_URL`. Unless the phone is on that exact private LAN, the restore request can fail or time out, exposing the worst-case path for logged-in users.

The app also has no `usesCleartextTraffic` or network-security configuration. Android's `targetSdkVersion 36` default policy normally disables platform cleartext traffic, but Flutter's `dart:io` HTTP client has its own network stack and Flutter documents that platform cleartext policy is not enforced at the Dart socket level. Therefore cleartext blocking is **not proven** to be the cause of a failed request here; the hardcoded private endpoint is the definite release-startup risk. Cleartext/network security remains a release-hardening item, not a confirmed delay cause.

---

## Current startup timeline

| Step | What happens | Evidence |
|---|---|---|
| 1 | Process starts; Flutter registers all Android plugins | `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java:17-70` |
| 2 | Dart `main()` runs; `WidgetsFlutterBinding.ensureInitialized()` | `lib/main.dart:31-32` |
| 3 | **Awaited** `Firebase.initializeApp()` blocks `runApp()` | `lib/main.dart:34-36` |
| 4 | `runApp()` builds `MaterialApp`; both light and dark `ThemeData` objects are constructed | `lib/main.dart:38-62`, `146-148`; `lib/core/theme/app_theme.dart:8,70` |
| 5 | Splash `initState` starts a 2,000 ms animation and calls `_bootstrap()` | `lib/features/auth/splash_screen.dart:26-31,66-67` |
| 6 | `_bootstrap()` awaits `AuthProvider.tryRestoreSession()` | `lib/features/auth/splash_screen.dart:70-75` |
| 7 | Restore reads `SharedPreferences`; if access token exists, calls `GET /auth/me` | `lib/logic/auth_provider.dart:28-40`; `lib/data/remote/auth_service.dart:109-117` |
| 8 | Request is wrapped in a 20 s timeout; expired access token may trigger refresh and retry | `lib/data/remote/api_client.dart:28,133-152,191-198,201-243` |
| 9 | After restore resolves, splash awaits a fixed 2,500 ms delay | `lib/features/auth/splash_screen.dart:77-78` |
| 10 | Navigation to role dashboard or login | `lib/features/auth/splash_screen.dart:80-86` |
| 11 | Dashboard mounts; admin starts SQLite + three sequential role API calls and a conditional Firestore write | `lib/features/admin/admin_dashboard.dart:50-60,69-90`; `lib/logic/member_provider.dart:32-48` |

---

## Findings

### F1 — Fixed 2,500 ms splash delay is added after session restore completes

**Severity:** Critical  
**File:** `lib/features/auth/splash_screen.dart:70-78`

**Exact code responsible:**

```dart
Future<void> _bootstrap() async {
  try {
    final auth = context.read<AuthProvider>();

    // Perform session restoration
    final user = await auth.tryRestoreSession();

    // Minimum splash time to ensure animation completes
    await Future.delayed(const Duration(milliseconds: 2500));
```

The splash animation itself is 2,000 ms:

```dart
// lib/features/auth/splash_screen.dart:28-31
_controller = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 2000),
);
```

**Why it delays startup:**  
`Future.delayed` starts only after `tryRestoreSession()` completes. Therefore the splash duration is `sessionRestoreTime + 2500 ms`, not `max(sessionRestoreTime, 2500 ms)`. Even a user with no stored session waits 2.5 seconds after the first frame before the login screen appears.

**Recommended fix:**  
Run the minimum-display timer and session restore concurrently, then navigate when both have finished. Use a much shorter minimum (for example 500–800 ms) and do not keep the splash visible for the full animation if restore is already complete. The animation can finish during the transition or be shortened.

**Expected benefit:**  
Removes a deterministic **2.5 s** from every cold start. With a 600 ms minimum, the idle-session path becomes roughly `max(restore, 0.6 s)` instead of `restore + 2.5 s`.

---

### F2 — Splash blocks on a remote profile request with a 20-second timeout and no offline fallback

**Severity:** Critical  
**Files:**

- `lib/features/auth/splash_screen.dart:75`
- `lib/logic/auth_provider.dart:28-40`
- `lib/data/remote/auth_service.dart:109-117`
- `lib/data/remote/api_client.dart:28,133-152,191-198,201-243`

**Exact code responsible:**

```dart
// splash_screen.dart:75
final user = await auth.tryRestoreSession();
```

```dart
// auth_provider.dart:28-42
Future<AppUser?> tryRestoreSession() async {
  if (!await _authService.hasStoredSession()) return null;
  try {
    final profile = await _authService.getCurrentUserProfile();
    if (profile != null && profile.isApproved) {
      _currentUser = profile;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return _currentUser;
    }
    return null;
  } catch (_) {
    return null;
  }
}
```

```dart
// auth_service.dart:109-117
Future<AppUser?> getCurrentUserProfile() async {
  try {
    final res = await _api.get('/auth/me');
    _currentUser = _mapApiUser(res);
    return _currentUser;
  } catch (e) {
    return null;
  }
}
```

```dart
// api_client.dart:28
static const Duration _requestTimeout = Duration(seconds: 20);
```

```dart
// api_client.dart:133-152
Future<http.Response> _send(Future<http.Response> request) async {
  try {
    return await request.timeout(_requestTimeout);
  } on TimeoutException {
    throw ApiException(
      'The API request timed out. Check that the TaleemPlus backend is '
      'running at $baseUrl and try again.',
    );
  }
  ...
}
```

The request path can also become multiple sequential requests when the access token is expired:

```dart
// api_client.dart:191-198
var response = await send();
final mayRefresh = withAuth &&
    response.statusCode == 401 &&
    !endpoint.startsWith('/auth/refresh') &&
    !endpoint.startsWith('/auth/login') &&
    !endpoint.startsWith('/auth/register');
if (mayRefresh && await _refreshSession()) response = await send();
```

**Why it delays startup:**  
The first user-visible screen waits for a server response before it can decide where to navigate. There is no local cached profile, no short bootstrap-specific timeout, and no offline path. If the backend is unreachable, the user can sit on the splash for up to 20 seconds before being sent to login. If the token is expired, the app may also perform a refresh and a retry, adding more sequential round trips.

This also contradicts the repository’s “offline-first” description: session restoration is online-first and has no cache fallback.

**Recommended fix:**  
Make session restoration local-first:

- Cache the last approved `AppUser` profile (encrypted storage or at minimum `SharedPreferences`) and restore it immediately.
- Use a short bootstrap timeout (for example 2–3 s) for `/auth/me`; do not use the general 20 s request timeout for startup.
- If the token exists but the profile cannot be refreshed, allow the cached profile to open the app and refresh silently in the background.
- Optionally check connectivity before making the bootstrap request.
- Do not let a failed background refresh clear the local session until the user is actually signed out.

**Expected benefit:**  
Removes up to **20 s** from the failure path and removes the network round trip from the normal splash path. A returning user reaches the dashboard from local state almost immediately; a stale session falls back to login after a short bounded wait.

---

### F3 — Release Android uses a hardcoded private HTTP LAN URL; cleartext policy is not configured

**Severity:** High  
**Files:**

- `lib/data/remote/api_client.dart:26-27,31-51`
- `android/app/src/main/AndroidManifest.xml:6-9`
- Merged release manifest: `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml:9,44-49`
- CI workflows that build release APKs without `API_BASE_URL`: `.github/workflows/android-apk.yml:33`, `.github/workflows/android-ci.yml:86`, `.github/workflows/main.yml:80`, `.github/workflows/flutter-ci.yml:71`

**Exact code responsible:**

```dart
// api_client.dart:26-27
static const String _configuredBaseUrl =
    String.fromEnvironment('API_BASE_URL');
```

```dart
// api_client.dart:48-50
return defaultTargetPlatform == TargetPlatform.android
    ? 'http://192.168.10.9:5000/api/v2'
    : 'http://localhost:5000/api/v2';
```

Merged release manifest:

```xml
<!-- build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml:7-9 -->
<uses-sdk
    android:minSdkVersion="24"
    android:targetSdkVersion="36" />
```

```xml
<!-- AndroidManifest.xml:6-9 -->
<application
    android:label="Taleem Plus"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```

There is no `android:usesCleartextTraffic="true"` and no `android:networkSecurityConfig` in the source or merged release manifest.

Android's default cleartext policy for `targetSdkVersion 36` normally disables HTTP for platform HTTP clients. However, Flutter documents that its platform network policy applies to platform-native sockets and that Dart/Flutter-owned sockets are not subject to it; `package:http` uses `dart:io`/`HttpClient` on Android by default. **Cleartext blocking is therefore not proven for this app's API client.** The finding is the hardcoded private endpoint and the absence of a production API origin, not a confirmed cleartext failure.

**Why it delays startup:**  
A release APK built without `--dart-define=API_BASE_URL=...` uses the hardcoded private LAN address. On a physical phone that is not on the developer’s `192.168.10.9` network, the session-restore request can fail, hang, or time out. Combined with F2, this turns the splash into a long wait or a failed restore followed by login.

None of the checked-in release workflows supply `API_BASE_URL`, so the default HTTP LAN address is what ships unless the APK was built manually with an override.

**Recommended fix:**  
- Always inject an HTTPS production API origin at build time, e.g. `--dart-define=API_BASE_URL=https://api.example.com/api/v2`.
- Add separate debug/release build flavors or CI environment values.
- Keep release on HTTPS. If local HTTP is needed for debug only, use a debug-only network-security config.
- Add a build-time assertion or startup check that the release build is not using the hardcoded LAN URL.

**Expected benefit:**  
Eliminates the failed/timeout path for session restore and makes the API reachable from real devices. This does not itself make Flutter faster, but it prevents the 20-second worst-case path from being the normal path in release.

**Note on `INTERNET` permission:**  
The source manifest declares only `CAMERA` (`AndroidManifest.xml:4`), but the merged release manifest contains `INTERNET` at line 35, added transitively by `firebase-auth` and `firebase-firestore` (`build/app/outputs/logs/manifest-merger-release-report.txt:626-629`). So the current merged release APK is not missing `INTERNET`, but the permission is fragile. See F7.

---

### F4 — Firebase is initialized before `runApp()` although no startup screen needs it

**Severity:** High  
**File:** `lib/main.dart:31-36`  
**Related:** `lib/firebase_options.dart:41-56`; `lib/main.dart:38-62`

**Exact code responsible:**

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
```

Checked-in Android options are placeholders:

```dart
// firebase_options.dart:50-56
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIzaSyPlaceholderApiKeyForTaleemPlusAndroid',
  appId: '1:000000000000:android:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'taleemplus-40755',
  storageBucket: 'taleemplus-40755.appspot.com',
);
```

Firebase is still used later by several features:

- `lib/data/remote/announcement_service.dart:9-16`
- `lib/data/remote/timetable_service.dart:5`
- `lib/data/remote/notification_service.dart:5`
- `lib/data/remote/academic_structure_service.dart:8`
- `lib/data/repositories/class_section_repository.dart:14-17`
- `lib/data/repositories/class_report_repository.dart:6-8`
- `lib/features/ocr/services/ocr_firestore_service.dart:5`
- `lib/features/admin/admin_dashboard.dart:80`

**Why it delays startup:**  
`Firebase.initializeApp()` is an awaited platform-channel call before `runApp()`. While no provider or startup screen uses Firebase to render the first Flutter frame, the app still pays the native Firebase initialization cost before it can draw anything. On a cold start this extends the Android launch window.

The checked-in placeholder options also mean a locally built release APK initializes Firebase with invalid credentials unless CI injects a real `FIREBASE_OPTIONS` file. That is a correctness risk separate from timing, but it makes Firebase-dependent dashboard calls fail after startup.

**Recommended fix:**  
Do not block the first frame on Firebase. Options:

- Call `runApp()` immediately after `WidgetsFlutterBinding.ensureInitialized()`.
- Start `Firebase.initializeApp()` in the background after the first frame, or lazily await it before the first Firestore-dependent feature is used.
- Keep a single shared `Future<FirebaseApp>` so all callers await the same initialization.
- If startup logic must await Firebase, do it concurrently with the splash/session bootstrap, not before `runApp()`.
- Do not remove Firebase packages; migrate remaining Firestore calls separately.

**Expected benefit:**  
Removes native Firebase initialization from the pre-first-frame critical path. The exact saving is device- and Firebase-version-dependent and must be measured; no precise millisecond claim is made here. It also makes the startup sequence less likely to expose invalid placeholder credentials before the UI is ready.

---

### F5 — Admin dashboard startup performs sequential local + network loads and a conditional Firestore write

**Severity:** High  
**Files:**

- `lib/features/admin/admin_dashboard.dart:50-60,69-90`
- `lib/logic/member_provider.dart:32-48`

**Exact code responsible:**

```dart
// admin_dashboard.dart:50-60
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final members = Provider.of<MemberProvider>(context, listen: false);
      final user = auth.currentUser;
      if (user != null) {
        members.load(user.uid);
        _verifyLegacyAdminData(user);
      }
    }
  });
}
```

```dart
// admin_dashboard.dart:69-90
Future<void> _verifyLegacyAdminData(AppUser user) async {
  if (user.academyCode == null || user.academyId == null) {
    try {
      final newCode = "TP-${user.uid.substring(0, 5).toUpperCase()}";
      await AuthService().updateAcademyProfile(...);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({...});

      if (mounted) {
        context.read<AuthProvider>().tryRestoreSession();
      }
    } catch (e) {
      debugPrint('Legacy admin data migration failed: $e');
    }
  }
}
```

```dart
// member_provider.dart:37-48
final sqliteMembers =
    kIsWeb ? <AcademyMember>[] : await _repo.getAll(academyId);

final firestoreTeachers =
    await _authService.getApprovedByRole(academyId, UserRole.teacher);
final firestoreStudents =
    await _authService.getApprovedByRole(academyId, UserRole.student);
final firestoreParents =
    await _authService.getApprovedByRole(academyId, UserRole.parent);
```

`AuthService.getApprovedByRole` delegates to `getUsersByRole`, which performs one HTTP GET per role:

```dart
// auth_service.dart:147-163
final res = await _api.get('/users/by-role?role=${role.name}');
```

**Why it delays startup:**  
After the splash finishes, the admin dashboard mounts and starts:

1. A SQLite open/read.
2. Three sequential HTTP requests for teacher/student/parent users.
3. A conditional Firestore profile update and then another `/auth/me` call.

The three role requests are sequential even though they are independent. On a typical mobile round trip this adds two unnecessary network waits before the dashboard counts are ready. The legacy migration path adds a Firestore write and a second session restore, both of which compete with dashboard rendering.

**Recommended fix:**  
- Fetch the three roles concurrently with `Future.wait` or replace them with one aggregate endpoint such as `/users/counts`.
- Run the legacy data migration after the first dashboard paint, or defer it to an idle/background task; do not do it during startup.
- Avoid calling `tryRestoreSession()` just to update local state after the Firestore write.
- Keep the dashboard skeleton visible while the counts load; do not block navigation on counts.

**Expected benefit:**  
Removes up to **two round trips** from the admin time-to-data path (for example, on a 150–300 ms mobile RTT, roughly 300–600 ms), and avoids a Firestore write plus a second profile request on affected accounts.

---

### F6 — All plugins, including ML Kit, printing, and `integration_test`, are registered eagerly

**Severity:** Medium  
**Files:**

- `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java:17-70`
- `pubspec.yaml:24-26,31-33,51-56,61-64`

**Exact code responsible:**

```java
// GeneratedPluginRegistrant.java (abridged)
flutterEngine.getPlugins().add(new io.flutter.plugins.firebase.firestore.FlutterFirebaseFirestorePlugin());
flutterEngine.getPlugins().add(new dev.fluttercommunity.plus.connectivity.ConnectivityPlugin());
flutterEngine.getPlugins().add(new io.flutter.plugins.firebase.auth.FlutterFirebaseAuthPlugin());
flutterEngine.getPlugins().add(new io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin());
flutterEngine.getPlugins().add(new com.google_mlkit_commons.GoogleMlKitCommonsPlugin());
flutterEngine.getPlugins().add(new com.google_mlkit_text_recognition.GoogleMlKitTextRecognitionPlugin());
flutterEngine.getPlugins().add(new io.flutter.plugins.imagepicker.ImagePickerPlugin());
flutterEngine.getPlugins().add(new dev.flutter.plugins.integration_test.IntegrationTestPlugin());
flutterEngine.getPlugins().add(new com.github.dart_lang.jni.JniPlugin());
flutterEngine.getPlugins().add(new com.github.dart_lang.jni_flutter.JniFlutterPlugin());
flutterEngine.getPlugins().add(new io.flutter.plugins.localauth.LocalAuthPlugin());
flutterEngine.getPlugins().add(new net.nfet.flutter.printing.PrintingPlugin());
flutterEngine.getPlugins().add(new io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin());
flutterEngine.getPlugins().add(new com.tekartik.sqflite.SqflitePlugin());
flutterEngine.getPlugins().add(new io.flutter.plugins.urllauncher.UrlLauncherPlugin());
```

**Why it delays startup:**  
Flutter registers every Android plugin before Dart `main()` executes. Heavy plugins such as ML Kit text recognition, Firestore, printing, and JNI add native initialization and library loading to the process startup. `integration_test` is a dev dependency (`pubspec.yaml:61-62`) but its plugin is present in the generated release registrant.

This does not prove a specific millisecond cost, but it is directly on the pre-`main` path and is therefore part of cold-start time.

**Recommended fix:**  
- Audit which plugins are actually needed at startup and remove unused packages (this audit does not change them).
- Keep `integration_test` out of release plugin registration if the current Flutter tooling allows a debug/test-only flavor.
- Plan to move ML Kit OCR behind an on-demand feature/module if possible; Flutter plugin registration itself is eager, so true lazy loading may require a separate engine or platform-specific implementation.
- Measure plugin registration cost with `flutter run --trace-startup` and Android Macrobenchmark before/after any change.

**Expected benefit:**  
Device-dependent. Reducing eager native initialization should reduce pre-`main` time and memory, but the exact benefit must be measured rather than assumed.

---

### F7 — `INTERNET` is only transitive in the release manifest; it is not declared by the app

**Severity:** Medium  
**Files:**

- `android/app/src/main/AndroidManifest.xml:4` (only `CAMERA` declared)
- `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml:35`
- `build/app/outputs/logs/manifest-merger-release-report.txt:626-629`

**Exact evidence:**

```xml
<!-- Source: android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA"/>
```

```xml
<!-- Merged release manifest, line 35 -->
<uses-permission android:name="android.permission.INTERNET" />
```

The merger report says this permission was added by `firebase-auth:23.2.1` and merged from `firebase-firestore:25.1.4`.

**Why it delays startup:**  
It does not currently delay startup because the merged release manifest has the permission. The risk is fragility: if Firebase packages are later removed or their manifests change, the release app will silently lose network access, and the startup restore path will fail. An earlier audit statement that “release cannot reach the API because `INTERNET` is missing” is not supported by the current merged manifest; the actual release networking problem is the hardcoded private API URL in F3. The missing cleartext configuration is a secondary hardening concern, not a proven blocker for Flutter’s `dart:io` client.

**Recommended fix:**  
Declare `<uses-permission android:name="android.permission.INTERNET"/>` explicitly in `android/app/src/main/AndroidManifest.xml`.

**Expected benefit:**  
No direct startup-time change. It prevents a future release-only networking regression and makes the app’s network requirement explicit.

---

### F8 — Root `Consumer2` rebuilds `MaterialApp` and constructs both themes on auth/theme notifications

**Severity:** Medium  
**Files:**

- `lib/main.dart:127-148`
- `lib/core/theme/app_theme.dart:8-68,70-128`
- `lib/logic/theme_provider.dart:19-34`

**Exact code responsible:**

```dart
// main.dart:127-148
return Consumer2<ThemeProvider, AuthProvider>(
  builder: (context, theme, auth, _) {
    ...
    return MaterialApp(
      ...
      theme: kIsWeb ? AppWebTheme.light : AppTheme.light,
      darkTheme: kIsWeb ? AppWebTheme.dark : AppTheme.dark,
      themeMode: theme.themeMode,
```

`AppTheme.light` and `AppTheme.dark` are getters that build complete `ThemeData` objects:

```dart
// app_theme.dart:8,70
static ThemeData get dark {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(...);
}

static ThemeData get light {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(...);
}
```

**Why it delays startup:**  
On the first build both `AppTheme.light` and `AppTheme.dark` are constructed, even though only one is used initially. The root `Consumer2` also rebuilds the entire `MaterialApp` whenever `AuthProvider` notifies (for example when session restore completes) or `ThemeProvider` loads the saved theme. Each rebuild reconstructs both large `ThemeData` objects synchronously.

This is not a multi-second cost, but it is unnecessary work on the startup path and can cause a visible theme flash if the saved theme differs from the initial system theme.

**Recommended fix:**  
- Cache `static final ThemeData light` and `dark` in `AppTheme`.
- Split the `Consumer` so only the `MaterialApp` theme depends on `ThemeProvider`, not on unrelated auth status changes.
- Avoid notifying listeners for theme changes unless the mode actually changed.

**Expected benefit:**  
Small but measurable reductions in first-frame and post-restore rebuild cost; less startup jank. Exact milliseconds are device-dependent.

---

### F9 — Splash logo is a 1024×1024, 328 KB asset displayed at 180×180 without decode sizing

**Severity:** Low  
**File:** `lib/features/auth/splash_screen.dart:133-136`  
**Asset evidence:** `assets/images/splash_logo.png` is 1024×1024 and 328,232 bytes.

**Exact code responsible:**

```dart
Image.asset(
  'assets/images/splash_logo.png',
  fit: BoxFit.cover,
),
```

The image is placed inside a `180 × 180` container (`splash_screen.dart:118-130`).

**Why it delays startup:**  
Flutter decodes the full 1024×1024 PNG even though it is displayed at 180×180. A 1024×1024 RGBA image is roughly 4 MB in memory before GPU upload. This can add decode/upload work and cause a blank or janky early splash frame on low-end devices. It does not block the first Flutter frame by itself, but it affects how quickly the splash looks complete.

**Recommended fix:**  
- Resize the asset to the largest displayed size (for example 360×360 for 2× density) or use a vector/`flutter_native_splash` asset.
- Supply `cacheWidth`/`cacheHeight` to `Image.asset` so the decoded image matches the display size.
- Precache the image if it must be shown immediately.

**Expected benefit:**  
Reduces decoded memory from roughly 4 MB to roughly 0.5 MB and lowers image decode/upload cost. The visible improvement is device-dependent.

---

### F10 — Native launch screen is a generic white/black background, not the branded splash

**Severity:** Low  
**Files:**

- `android/app/src/main/res/values/styles.xml:4-7,15-17`
- `android/app/src/main/res/values-night/styles.xml:4-7`
- `android/app/src/main/res/drawable-v21/launch_background.xml:4`

**Exact code responsible:**

```xml
<!-- values/styles.xml -->
<style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@drawable/launch_background</item>
</style>
```

```xml
<!-- drawable-v21/launch_background.xml -->
<item android:drawable="?android:colorBackground" />
```

**Why it delays startup:**  
It does not add actual startup time, but it creates a white (light mode) or black (dark mode) window before Flutter draws the teal splash. On a slow cold start this makes the launch feel longer and can produce a visible color flash.

**Recommended fix:**  
- Set the launch window background to the brand color (`#061F1E`) instead of `?android:colorBackground`.
- Use the Android 12+ `SplashScreen` API (`windowSplashScreenBackground`, `windowSplashScreenAnimatedIcon`) or `flutter_native_splash` so the native splash matches the Flutter splash.
- Keep the native splash simple; do not add work there.

**Expected benefit:**  
No measured time reduction, but removes the blank flash and improves perceived launch responsiveness.

---

### F11 — Startup performs unawaited `SharedPreferences` reads and a write

**Severity:** Low  
**Files:**

- `lib/logic/theme_provider.dart:19-34`
- `lib/logic/session_provider.dart:31-34,87-92`

**Exact code responsible:**

```dart
// theme_provider.dart:19-34
ThemeProvider() {
  _loadTheme();
}

Future<void> _loadTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString(_themeKey);
  ...
}
```

```dart
// session_provider.dart:31-34
SessionProvider() {
  _loadBiometricPref();
  WidgetsBinding.instance.addObserver(this);
}
```

```dart
// session_provider.dart:87-92
Future<void> _loadBiometricPref() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('saved_pass_v1');
  _biometricEnabled = prefs.getBool(_biometricKey) ?? false;
  notifyListeners();
}
```

**Why it delays startup:**  
These calls are asynchronous and do not block `runApp()`, but they start during the first frame/early navigation. `SharedPreferences.getInstance()` loads the preference file, and `prefs.remove('saved_pass_v1')` performs a write on every launch even when the legacy key is absent. Multiple components request the same preferences independently.

**Recommended fix:**  
- Load preferences once in a small bootstrap service and pass the values to providers.
- Remove the legacy key only when it exists (`containsKey`) rather than writing every launch.
- Avoid calling `notifyListeners()` if the loaded value did not change.

**Expected benefit:**  
Small; removes unnecessary startup disk I/O and allocations. Not a multi-second fix.

---

## Five highest-priority problems

| Rank | Finding | Why it is highest priority | Primary location |
|---|---|---|---|
| 1 | **F1 — Fixed 2.5 s splash delay after restore** | Adds a deterministic 2.5 s to every cold start, including users with no session. It is the largest guaranteed cost. | `lib/features/auth/splash_screen.dart:75-78` |
| 2 | **F2 — Remote session restore blocks startup with a 20 s timeout** | Turns the splash into a network wait; can add up to 20 s on a bad/unreachable backend and has no offline cache. | `lib/features/auth/splash_screen.dart:75`; `lib/logic/auth_provider.dart:28-40`; `lib/data/remote/api_client.dart:28,133-152` |
| 3 | **F3 — Release points at a hardcoded private HTTP LAN URL** | Makes F2’s worst case likely on a physical release device; not a UI performance issue but a release startup correctness issue. Cleartext blocking is unproven for Flutter’s Dart HTTP client. | `lib/data/remote/api_client.dart:48-50`; release workflows that omit `API_BASE_URL` |
| 4 | **F4 — Firebase initialized before `runApp()`** | Firebase initialization is on the pre-first-frame critical path even though no startup screen needs it. | `lib/main.dart:31-36` |
| 5 | **F5 — Admin dashboard startup does sequential loads and a Firestore write** | Adds avoidable SQLite + network work immediately after splash; three role requests run one after another. | `lib/features/admin/admin_dashboard.dart:50-60`; `lib/logic/member_provider.dart:32-48` |

F6 (eager plugin registration) is the next candidate if the first five are addressed and the cold start is still slow; it needs on-device measurement to prioritize against F5.

---

## Verified non-issues and positives

These were checked and are **not** current startup problems:

- **`WidgetsFlutterBinding.ensureInitialized()` is called correctly** once at `lib/main.dart:32`, before Firebase and `runApp`.
- **Only one `Firebase.initializeApp()` call exists** in `lib/` (`lib/main.dart:34`). No duplicate initialization was found.
- **Firebase is still required by the current codebase**, but not by the first frame: Firestore is used by announcements, timetable, notifications, academic structure, class sections/reports, OCR, and the admin dashboard. The correct move is deferral, not removal.
- **No database is opened before `runApp()`.** `DbHelper` opens SQLite lazily (`lib/data/local/db_helper.dart:14-28`); the first open is on the admin dashboard path.
- **No API call is made before `runApp()`.** The first network request is the splash session restore, after the first Flutter frame.
- **The merged release manifest does contain `INTERNET`** (line 35), added by Firebase dependencies. The source manifest should still declare it explicitly (F7).
- **Cleartext blocking is not counted as a confirmed startup defect.** The 20-second timeout risk comes from the hardcoded private API endpoint (F3), not from proven cleartext rejection. Flutter documents that platform cleartext policy applies to platform-native sockets, while `package:http` uses Flutter's own `dart:io` HTTP stack on Android.
- **`MainActivity` contains no custom blocking initialization** (`android/app/src/main/kotlin/com/example/taleem_plus/MainActivity.kt:1-5`); it only extends `FlutterFragmentActivity`, which is required by `local_auth`.
- **Release R8/minification is enabled** (`android/app/build.gradle.kts:57-72`), and the built APK metadata includes baseline profiles for API 28–30 and 31+ (`build/app/outputs/apk/release/output-metadata.json`). No missing baseline profile was found.
- **Google Fonts are web-only.** `google_fonts` is imported in `lib/core/web/web_theme.dart`, and mobile uses `AppTheme`; no mobile font download is initiated at startup.
- **`ParentProvider.syncWithUser()` does not perform a network request in the current `AuthService`.** `watchProfile` yields `_currentUser` and `getProfilesByIds` returns an empty list (`lib/data/remote/auth_service.dart:187-189,317-319`), so the ProxyProvider update is not a startup network cost today.

---

## Recommended target startup sequence

The goal is to make the first screen independent of network and Firebase:

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. `runApp()` immediately.
3. Show the Flutter splash with a short minimum duration (for example 500–800 ms).
4. Start Firebase initialization and session restoration concurrently, after the first frame.
5. Restore the cached user immediately; refresh `/auth/me` with a short bootstrap timeout in the background.
6. Navigate as soon as `max(minimumSplash, localRestore)` completes; do not wait for the full 2.5 s animation.
7. Start dashboard data loads after the first dashboard frame; show skeletons rather than blocking navigation.
8. Fetch independent dashboard resources concurrently, or use aggregate endpoints.

---

## On-device measurement plan

Because no device was attached during this audit, the exact millisecond attribution still needs confirmation:

1. Build a release/profile APK with a valid HTTPS `API_BASE_URL` and valid Firebase options.
2. Run `flutter run --profile --trace-startup` on the physical phone and capture `startup_timeline.json`.
3. Use Android Macrobenchmark `StartupTimingMetric` for cold-start iteration:
   - Warm-up iterations.
   - At least 5 cold-start iterations.
   - Compare “no stored session” vs “stored session, backend reachable” vs “stored session, backend unreachable.”
4. Measure the same APK after each proposed change:
   - F1 only (splash delay)
   - F1 + F2 (local-first restore)
   - F1 + F2 + F4 (deferred Firebase)
5. Record `Time to first frame`, `Time to initial display`, and `Time to login/dashboard` separately.

Suggested acceptance targets:

- No-session cold start to usable login: under 2 seconds on a mid-range device.
- Returning-session cold start to dashboard: under 2.5 seconds with a reachable backend.
- Backend-unreachable cold start: under 3 seconds to cached dashboard or login, never 20+ seconds.

---

## Key code references

| Area | File and lines |
|---|---|
| Entry point / Firebase await / providers | `lib/main.dart:31-62` |
| Root rebuild and theme construction | `lib/main.dart:127-148`; `lib/core/theme/app_theme.dart:8,70` |
| Splash animation and bootstrap | `lib/features/auth/splash_screen.dart:26-31,66-92` |
| Splash fixed delay | `lib/features/auth/splash_screen.dart:75-78` |
| Session restore | `lib/logic/auth_provider.dart:28-42` |
| `/auth/me` call | `lib/data/remote/auth_service.dart:109-117` |
| API timeout and retry/refresh | `lib/data/remote/api_client.dart:28,133-152,191-243` |
| Hardcoded Android API URL | `lib/data/remote/api_client.dart:48-50` |
| Firebase placeholder options | `lib/firebase_options.dart:41-56` |
| Admin startup loads | `lib/features/admin/admin_dashboard.dart:50-60,69-90` |
| Sequential role requests | `lib/logic/member_provider.dart:32-48`; `lib/data/remote/auth_service.dart:147-163` |
| Theme/prefs startup work | `lib/logic/theme_provider.dart:19-34`; `lib/logic/session_provider.dart:31-34,87-92` |
| Splash image | `lib/features/auth/splash_screen.dart:133-136`; asset is 1024×1024, 328,232 bytes |
| Android launch theme | `android/app/src/main/res/values/styles.xml:4-17`; `drawable-v21/launch_background.xml:4` |
| Source manifest permissions | `android/app/src/main/AndroidManifest.xml:4,6-9` |
| Merged release permissions / SDK | `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml:7-9,35,44-49` |
| Eager plugin registration | `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java:17-70` |
