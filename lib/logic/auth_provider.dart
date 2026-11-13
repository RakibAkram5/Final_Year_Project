import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../data/models/app_user.dart';
import '../data/remote/api_client.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/branding_service.dart';

enum AuthStatus { idle, loading, authenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthProvider({AuthService? authService})
      : _authService = authService ?? AuthService();

  AuthStatus _status = AuthStatus.idle;
  AppUser? _currentUser;
  String? _errorMessage;
  bool _pendingApproval = false;

  AuthStatus get status => _status;
  AppUser? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _currentUser != null;
  bool get pendingApproval => _pendingApproval;

  /// Restores the session from local state first so the splash never has to
  /// wait for the network. The profile is then refreshed silently in the
  /// background; a transient outage keeps the cached session instead of
  /// signing the user out.
  Future<AppUser?> tryRestoreSession() async {
    if (!await _authService.hasStoredSession()) {
      await _authService.clearCachedUser();
      return null;
    }

    final cached = await _authService.getCachedUser();
    if (cached != null && cached.isApproved) {
      _currentUser = cached;
      _status = AuthStatus.authenticated;
      notifyListeners();
      unawaited(_refreshProfileSilently());
      return _currentUser;
    }

    try {
      final profile = await _authService.getCurrentUserProfile(
        timeout: const Duration(seconds: 4),
      );
      if (profile != null && profile.isApproved) {
        _currentUser = profile;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return _currentUser;
      }
    } catch (_) {
      // No cached profile and the backend is unreachable: fall back to login.
    }
    return null;
  }

  Future<void> _refreshProfileSilently() async {
    try {
      final profile = await _authService.getCurrentUserProfile(
        timeout: const Duration(seconds: 8),
      );
      if (profile == null) return;
      // The user signed out or switched accounts while the refresh was in
      // flight; never resurrect the old session.
      if (_currentUser == null || _currentUser!.uid != profile.uid) return;
      if (profile.isApproved) {
        _currentUser = profile;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return;
      }
      // The account is no longer active: clear the stale session.
      await _authService.signOut();
      _currentUser = null;
      _status = AuthStatus.idle;
      notifyListeners();
    } on ApiException catch (e) {
      // 401/403 here means the access token could not be refreshed (refresh
      // token revoked or expired) or the account was deactivated: the cached
      // session is dead and must not be kept.
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _authService.signOut();
        _currentUser = null;
        _status = AuthStatus.idle;
        notifyListeners();
      }
      // Other API errors (5xx, timeouts) keep the cached session.
    } catch (_) {
      // Network/auth transport failure: keep the cached session.
    }
  }

  /// Called when the app returns to the foreground: refreshes the access
  /// token proactively and re-validates the profile so a session that sat in
  /// the background past the 15-minute access-token lifetime keeps working.
  Future<void> onAppResumed() async {
    if (_currentUser == null) return;
    await _authService.refreshSessionIfPossible();
    await _refreshProfileSilently();
  }

  /// Returns true only when the user is approved and should enter a dashboard.
  /// Returns false for errors OR pending approval (check [pendingApproval]).
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required UserRole role,
    String? academyName,
    String? academyId,
    String? academyCode,
    String? academyAddress,
    String? academyPhone,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    _setLoading();
    try {
      final user = await _authService.signUp(
        fullName: fullName,
        email: email,
        phoneNumber: phoneNumber,
        password: password,
        role: role,
        academyName: academyName,
        academyId: academyId,
        academyCode: academyCode,
        academyAddress: academyAddress,
        academyPhone: academyPhone,
        securityQuestion: securityQuestion,
        securityAnswer: securityAnswer,
      );

      if (!user.isApproved) {
        _pendingApproval = true;
        _currentUser = null;
        _status = AuthStatus.idle;
        notifyListeners();
        return false;
      }

      _currentUser = user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _setError(e.message);
      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    _setLoading();
    try {
      _currentUser = await _authService.signIn(email, password);
      _status = AuthStatus.authenticated;
      await _persistRememberMe(rememberMe, email);
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _setError(e.message);
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    _status = AuthStatus.idle;
    notifyListeners();
  }

  Future<String?> loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(DbKeys.prefRememberMe) ?? false) {
      return prefs.getString(DbKeys.prefSavedEmail);
    }
    return null;
  }

  Future<void> _persistRememberMe(bool remember, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DbKeys.prefRememberMe, remember);
    if (remember) {
      await prefs.setString(DbKeys.prefSavedEmail, email.trim());
    } else {
      await prefs.remove(DbKeys.prefSavedEmail);
    }
  }

  /// Self-service fix for an account scoped to the wrong academy_id (see
  /// [AuthService.relinkAcademy]). Refreshes [currentUser] in place so every
  /// screen watching this provider (announcements, dashboards, etc.)
  /// immediately re-queries under the corrected academy scope.
  Future<void> relinkAcademy(String code) async {
    if (_currentUser == null) {
      throw AuthException('No active session found.');
    }
    final updated = await _authService.relinkAcademy(_currentUser!.uid, code);
    _currentUser = updated;
    notifyListeners();
  }

  /// Admin: saves the academy location and updates [currentUser] so every
  /// screen showing the map refreshes immediately.
  Future<void> saveAcademyLocation(AcademyLocation? location,
      {String? address}) async {
    final saved =
        await _authService.saveAcademyLocation(location, address: address);
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(
        academyLocation: saved,
        clearAcademyLocation: saved == null,
        academyAddress: address,
      );
      notifyListeners();
    }
  }

  /// Admin: applies freshly saved academy branding to [currentUser] so every
  /// portal screen, sidebar and PDF uses the new identity immediately.
  Future<void> applyBranding(AcademyBranding branding) async {
    final updated = await _authService.applyBranding(branding);
    if (updated != null) {
      _currentUser = updated;
      notifyListeners();
    }
  }

  void clearError() {
    if (_status == AuthStatus.error) {
      _status = AuthStatus.idle;
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _setLoading() {
    _status = AuthStatus.loading;
    _errorMessage = null;
    _pendingApproval = false;
    notifyListeners();
  }

  void _setError(String message) {
    _status = AuthStatus.error;
    _errorMessage = message;
    notifyListeners();
  }
}
