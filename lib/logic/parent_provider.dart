import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../data/models/app_user.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/live_query.dart';

/// Linked children of the signed-in parent.
///
/// Source of truth is the server: `GET /auth/me` returns the parent's
/// `linkedChildren` (from the parent_student_relationships table) and
/// `POST /users/profiles` returns those students' profiles. The server only
/// ever returns students linked to *this* parent in *this* academy, so the
/// client never filters or guesses ids itself.
///
/// Fixes (Phase 5):
/// * [refresh] really re-fetches. Previously pull-to-refresh returned early
///   because a subscription already existed, so a child linked by the admin
///   after the parent signed in never appeared until the app restarted.
/// * Load failures are exposed through [error] instead of looking like
///   "no children linked".
/// * The profile is re-checked periodically while the app is open.
class ParentProvider extends ChangeNotifier {
  final AuthService _authService;
  ParentProvider({AuthService? authService})
      : _authService = authService ?? AuthService();

  static const Duration pollInterval = Duration(minutes: 2);

  List<AppUser> _children = [];
  bool _loading = false;
  String? _error;
  String? _parentUid;
  int _generation = 0;
  Timer? _poller;
  StreamSubscription<String>? _changes;

  List<AppUser> get children => _children;
  bool get loading => _loading;

  /// User-facing message of the last failed load, or null.
  String? get error => _error;

  /// Binds this provider to the logged-in parent (called by the provider
  /// proxy on every auth change).
  Future<void> syncWithUser(AppUser? parent) async {
    if (parent == null || parent.role != UserRole.parent) {
      _unbind();
      return;
    }
    if (_parentUid == parent.uid) return;
    _unbind(notify: false);
    _parentUid = parent.uid;
    _poller = Timer.periodic(pollInterval, (_) => refresh(silent: true));
    // Local link/unlink writes notify the users topic.
    _changes =
        DataChanges.on(DataTopics.users).listen((_) => refresh(silent: true));
    await refresh();
  }

  /// Re-fetches the parent's profile and linked children from the server.
  /// [silent] keeps the current list on screen while refreshing.
  Future<void> refresh({bool silent = false}) async {
    final parentUid = _parentUid;
    if (parentUid == null) return;
    final generation = ++_generation;
    if (!silent || _children.isEmpty) {
      _loading = true;
      notifyListeners();
    }
    try {
      final profile = await _authService.getCurrentUserProfile();
      if (generation != _generation || _parentUid != parentUid) return;
      if (profile == null || profile.uid != parentUid) {
        throw StateError('Signed-in profile does not match this parent.');
      }
      final ids = profile.linkedChildren;
      final kids =
          ids.isEmpty ? <AppUser>[] : await _authService.getProfilesByIds(ids);
      if (generation != _generation || _parentUid != parentUid) return;
      // Keep the server's link order (stable child switching).
      kids.sort((a, b) => ids.indexOf(a.uid).compareTo(ids.indexOf(b.uid)));
      _children = kids;
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('ParentProvider: failed to load linked children: $e');
      _error = 'Could not load your linked children. '
          'Check your connection and try again.';
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _unbind({bool notify = true}) {
    _generation++;
    _poller?.cancel();
    _poller = null;
    _changes?.cancel();
    _changes = null;
    _parentUid = null;
    _children = [];
    _error = null;
    _loading = false;
    if (notify) notifyListeners();
  }

  // Linking a child is an academy-admin action (User Management). The API
  // rejects parent self-linking, so the client has no method for it.

  Future<void> unlinkChild(String uid) async {
    if (_parentUid == null) return;
    await _authService.removeLinkedChild(_parentUid!, uid);
    await refresh(silent: true);
  }

  @override
  void dispose() {
    _unbind(notify: false);
    super.dispose();
  }
}
