import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// App-wide connectivity state shown by [ConnectionBanner].
///
/// Combines two signals: the platform connectivity (connectivity_plus) and
/// the outcome of real API calls, because a device can report Wi-Fi while
/// the backend is unreachable. Reports when a screen was served from the
/// offline read cache so the banner can say "showing saved data".
class ConnectionStatus extends ChangeNotifier {
  ConnectionStatus._() {
    _sub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivity, onError: (_) {});
  }
  static final ConnectionStatus instance = ConnectionStatus._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _deviceOffline = false;
  bool _apiUnreachable = false;
  DateTime? _lastServedFromCache;

  bool get isOffline => _deviceOffline || _apiUnreachable;

  /// When the most recent screen data came from the offline cache.
  DateTime? get lastServedFromCache => _lastServedFromCache;

  void _onConnectivity(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline != _deviceOffline) {
      _deviceOffline = offline;
      if (!offline) _apiUnreachable = false;
      notifyListeners();
    }
  }

  /// A request reached the backend (any HTTP status).
  void reportOnline() {
    if (_apiUnreachable || _lastServedFromCache != null) {
      _apiUnreachable = false;
      _lastServedFromCache = null;
      notifyListeners();
    }
  }

  /// A request failed before getting an HTTP status (no network / DNS /
  /// timeout). [fromCache] marks that cached data was shown instead.
  void reportUnreachable({bool fromCache = false}) {
    var changed = !_apiUnreachable;
    _apiUnreachable = true;
    if (fromCache) {
      _lastServedFromCache = DateTime.now();
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
