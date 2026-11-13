import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import 'auth_provider.dart';

class SessionProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const int _timeoutSeconds = 300;
  static const String _biometricKey = 'biometric_enabled';

  DateTime? _backgroundedAt;
  DateTime? _lastActivityAt;

  final LocalAuthentication _localAuth = LocalAuthentication();
  Timer? _timer;
  bool _isLocked = false;
  bool _biometricEnabled = false;
  AuthProvider? _auth;

  /// Set while the app has deliberately launched a sub-activity (camera,
  /// gallery picker, biometric prompt) that we expect to return control to
  /// us — those all trigger [AppLifecycleState.paused] just like genuinely
  /// backgrounding the app, but should never sign the user out no matter
  /// how long the user spends framing a photo or scrolling their gallery.
  int _suppressCount = 0;

  bool get isLocked => _isLocked;
  bool get biometricEnabled => _biometricEnabled;

  SessionProvider() {
    _loadBiometricPref();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void updateAuth(AuthProvider auth) {
    _auth = auth;
  }

  /// Call before launching a camera/gallery/biometric sub-activity so the
  /// resulting [AppLifecycleState.paused] isn't treated as backgrounding.
  /// Always pair with [resumeBackgroundLogoutTracking] in a `finally` block.
  void suppressBackgroundLogout() {
    _suppressCount++;
    _timer?.cancel();
  }

  void resumeBackgroundLogoutTracking() {
    if (_suppressCount > 0) _suppressCount--;
    if (_suppressCount == 0 && _auth?.isAuthenticated == true) {
      _lastActivityAt = DateTime.now();
      _startTimer(_timeoutSeconds);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_suppressCount > 0) return;
      _backgroundedAt ??= DateTime.now();
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (_auth?.isAuthenticated == true) {
        final lastActivityAt = _lastActivityAt ?? backgroundedAt;
        final elapsed = lastActivityAt == null
            ? 0
            : DateTime.now().difference(lastActivityAt).inSeconds;
        if (elapsed >= _timeoutSeconds) {
          _handleTimeout();
        } else {
          _startTimer(_timeoutSeconds - elapsed);
          // Access tokens live 15 minutes; refresh proactively so the first
          // request after resuming does not hit an expired-token error.
          unawaited(_auth!.onAppResumed());
        }
      }
    }
  }

  Future<void> _loadBiometricPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('saved_pass_v1')) {
      await prefs.remove('saved_pass_v1');
    }
    final enabled = prefs.getBool(_biometricKey) ?? false;
    if (_biometricEnabled != enabled) {
      _biometricEnabled = enabled;
      notifyListeners();
    }
  }

  Future<void> setBiometricEnabled(bool value, {String? password}) async {
    _biometricEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);

    // Older releases stored account passwords in plain SharedPreferences.
    // Remove that legacy value and rely on the backend refresh token instead.
    await prefs.remove('saved_pass_v1');

    notifyListeners();
  }

  Future<String?> getSavedPassword() async {
    return null;
  }

  void resetTimer(BuildContext context, AuthProvider auth) {
    _auth = auth;
    if (auth.isAuthenticated) _lastActivityAt = DateTime.now();
    if (_backgroundedAt != null) return;
    if (auth.isAuthenticated) {
      _startTimer(_timeoutSeconds);
    } else {
      _timer?.cancel();
    }
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: seconds), _handleTimeout);
  }

  void _handleTimeout() {
    _forceSignOut(
        'Your session has expired due to inactivity. Please log in again.');
  }

  /// Signs the user out, clears the lock flag once they land back on Login,
  /// and makes sure they actually see a screen + reason instead of silently
  /// losing their session mid-dashboard.
  void _forceSignOut(String message) {
    _isLocked = true;
    _auth?.signOut();
    notifyListeners();

    final nav = rootNavigatorKey.currentState;
    nav?.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isLocked = false;
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  Future<bool> authenticateWithBiometrics() async {
    suppressBackgroundLogout();
    try {
      final bool canAuthenticateWithBiometrics =
          await _localAuth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (!canAuthenticate) return false;

      return await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access TaleemPlus',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      debugPrint("Biometric Auth Error: $e");
      return false;
    } finally {
      resumeBackgroundLogoutTracking();
    }
  }

  void stopTimer() {
    _timer?.cancel();
  }
}
