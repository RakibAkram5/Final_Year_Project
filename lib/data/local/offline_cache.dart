import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Read-only offline cache for authenticated GET responses.
///
/// Scope (what TaleemPlus supports offline, documented in README):
///  * The last successful JSON response of every authenticated GET the user
///    performed is kept on the device, keyed by user and endpoint.
///  * When a request fails because the device is offline (no HTTP status),
///    [ApiClient] serves the cached copy and flags the app as offline.
///  * Writes (attendance, marks, uploads, quiz answers…) are NOT queued: they
///    fail with a clear error and must be retried online. This is deliberate –
///    a replayed write without the server's conflict checks could corrupt
///    attendance or fee records.
///
/// Entries are capped in size and count; the cache is wiped on sign-out so a
/// shared device never shows the previous user's data.
class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  static const _indexKey = 'tp_cache_index';
  static const _prefix = 'tp_cache:';
  static const int maxEntries = 150;
  static const int maxEntryBytes = 256 * 1024;

  /// Identifies whose data is cached (the signed-in user's id). Null disables
  /// caching entirely (not signed in).
  String? scope;

  String _key(String endpoint) => '$_prefix$scope:$endpoint';

  Future<void> write(String endpoint, dynamic data) async {
    if (scope == null) return;
    String encoded;
    try {
      encoded = jsonEncode({
        't': DateTime.now().millisecondsSinceEpoch,
        'd': data,
      });
    } catch (_) {
      return; // not JSON-serialisable (binary); skip
    }
    if (encoded.length > maxEntryBytes) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(endpoint);
      final index = (prefs.getStringList(_indexKey) ?? <String>[])
        ..remove(key)
        ..add(key);
      while (index.length > maxEntries) {
        await prefs.remove(index.removeAt(0));
      }
      await prefs.setString(key, encoded);
      await prefs.setStringList(_indexKey, index);
    } catch (_) {
      // Cache is best-effort; never let it break a live request.
    }
  }

  /// Returns the cached payload and its age, or null when nothing is cached.
  Future<CachedResponse?> read(String endpoint) async {
    if (scope == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(endpoint));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CachedResponse(
        data: decoded['d'],
        savedAt: DateTime.fromMillisecondsSinceEpoch(
            (decoded['t'] as num?)?.toInt() ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getStringList(_indexKey) ?? const <String>[]) {
        await prefs.remove(key);
      }
      await prefs.remove(_indexKey);
    } catch (_) {}
    scope = null;
  }
}

class CachedResponse {
  final dynamic data;
  final DateTime savedAt;
  const CachedResponse({required this.data, required this.savedAt});
}
