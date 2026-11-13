import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../logic/connection_status.dart';
import '../local/offline_cache.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  /// Override the API origin at build/run time without editing source:
  ///   flutter run -d chrome --dart-define=API_BASE_URL=https://api.example.com/api/v2
  /// During local development the per-platform defaults below are used.
  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL');
  static const Duration _requestTimeout = Duration(seconds: 20);

  // On Android emulator, localhost is 10.0.2.2; on web/iOS/desktop, it's localhost.
  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.endsWith('/')
          ? _configuredBaseUrl.substring(0, _configuredBaseUrl.length - 1)
          : _configuredBaseUrl;
    }
    if (kIsWeb) {
      final page = Uri.base;
      if ((page.scheme == 'http' || page.scheme == 'https') &&
          page.host != 'localhost' &&
          page.host != '127.0.0.1') {
        // Production and preview deployments serve the API from the same
        // origin, so no CORS configuration or rebuild is required.
        return '${page.origin}/api/v2';
      }
      return 'http://localhost:5000/api/v2';
    }
    if (kReleaseMode) {
      // Never ship a release build that silently points at a developer LAN
      // address: on a real device it hangs until the request timeout. Release
      // CI must pass --dart-define=API_BASE_URL=https://<host>/api/v2.
      throw StateError(
        'API_BASE_URL is not configured for this release build. Rebuild with '
        '--dart-define=API_BASE_URL=https://<your-api-host>/api/v2.',
      );
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://192.168.10.9:5000/api/v2'
        : 'http://localhost:5000/api/v2';
  }

  /// Centralised date parsing for REST payloads. Backend dates are ISO-8601
  /// strings; callers must not depend on Firestore Timestamp types.
  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim())?.toLocal();
    }
    return null;
  }

  static DateTime parseDateOr(dynamic value, DateTime fallback) =>
      parseDate(value) ?? fallback;

  static DateTime parseRequiredDate(dynamic value, {required String field}) {
    final parsed = parseDate(value);
    if (parsed == null) {
      throw FormatException('Missing or invalid date in field "$field".');
    }
    return parsed;
  }

  /// Formats a date for date-only backend fields such as attendance logDate.
  static String dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  /// Normalises backend enum values (for example PRESENT) to lowercase form.
  static String normalizeEnum(dynamic value) =>
      value == null ? '' : value.toString().toLowerCase();

  static const String _accessTokenKey = 'tp_access_token';
  static const String _refreshTokenKey = 'tp_refresh_token';
  Future<bool>? _refreshInProgress;

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  Future<String?> getStoredRefreshToken() => _getRefreshToken();

  Future<String?> _getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<void> setTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, access);
    await prefs.setString(_refreshTokenKey, refresh);
    _refreshToken = refresh;
    OfflineCache.instance.scope = _userIdFromJwt(access);
  }

  /// The `userId` claim of an access token (used to scope the offline cache
  /// to the signed-in user). Null when the token cannot be decoded.
  static String? _userIdFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final claims = jsonDecode(payload);
      return claims is Map ? claims['userId']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  /// Restores the offline-cache scope for an already stored session (app
  /// start). No-op when there is no token.
  Future<void> restoreCacheScope() async {
    if (OfflineCache.instance.scope != null) return;
    final token = await getAccessToken();
    if (token != null && token.isNotEmpty) {
      OfflineCache.instance.scope = _userIdFromJwt(token);
    }
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    _refreshToken = null;
    // Never leave the previous user's cached data on a shared device.
    await OfflineCache.instance.clear();
  }

  Future<Map<String, String>> _headers({bool withAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (withAuth) {
      final token = await getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<http.Response> _send(
    Future<http.Response> request, {
    Duration? timeout,
  }) async {
    try {
      return await request.timeout(timeout ?? _requestTimeout);
    } on TimeoutException {
      throw ApiException(
        'The API request timed out. Check that the TaleemPlus backend is '
        'running at $baseUrl and try again.',
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        'Could not reach the TaleemPlus API at $baseUrl. Make sure the '
        'backend is running and that CORS allows this origin. (${e.message})',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        'Network error while contacting the TaleemPlus API at $baseUrl: $e',
      );
    }
  }

  Future<dynamic> get(String endpoint,
      {bool withAuth = true, Duration? timeout}) async {
    return _request('GET', endpoint, withAuth: withAuth, timeout: timeout);
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body,
      {bool withAuth = true, Duration? timeout}) async {
    return _request('POST', endpoint,
        body: body, withAuth: withAuth, timeout: timeout);
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body,
      {bool withAuth = true, Duration? timeout}) async {
    return _request('PUT', endpoint,
        body: body, withAuth: withAuth, timeout: timeout);
  }

  Future<dynamic> delete(String endpoint,
      {bool withAuth = true, Duration? timeout}) async {
    return _request('DELETE', endpoint, withAuth: withAuth, timeout: timeout);
  }

  Future<dynamic> _request(String method, String endpoint,
      {Map<String, dynamic>? body,
      required bool withAuth,
      Duration? timeout}) async {
    Future<http.Response> send() async {
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _headers(withAuth: withAuth);
      final encoded = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'POST':
          return _send(http.post(uri, headers: headers, body: encoded),
              timeout: timeout);
        case 'PUT':
          return _send(http.put(uri, headers: headers, body: encoded),
              timeout: timeout);
        case 'DELETE':
          return _send(http.delete(uri, headers: headers), timeout: timeout);
        default:
          return _send(http.get(uri, headers: headers), timeout: timeout);
      }
    }

    final cacheable = method == 'GET' && withAuth;
    http.Response response;
    try {
      response = await send();
    } on ApiException catch (e) {
      // No HTTP status = the server was never reached (offline, DNS, timeout).
      if (e.statusCode == null) {
        if (cacheable) {
          await restoreCacheScope();
          final cached = await OfflineCache.instance.read(endpoint);
          if (cached != null) {
            ConnectionStatus.instance.reportUnreachable(fromCache: true);
            return cached.data;
          }
        }
        ConnectionStatus.instance.reportUnreachable();
      }
      rethrow;
    }
    ConnectionStatus.instance.reportOnline();
    final mayRefresh = withAuth &&
        _isAuthFailure(response) &&
        !endpoint.startsWith('/auth/refresh') &&
        !endpoint.startsWith('/auth/login') &&
        !endpoint.startsWith('/auth/register');
    if (mayRefresh && await _refreshSession()) response = await send();
    final result = _handleResponse(response);
    if (cacheable && response.statusCode >= 200 && response.statusCode < 300) {
      // Fire-and-forget: caching must never delay or fail a live response.
      unawaited(_cacheResponse(endpoint, result));
    }
    return result;
  }

  Future<void> _cacheResponse(String endpoint, dynamic data) async {
    try {
      await restoreCacheScope();
      await OfflineCache.instance.write(endpoint, data);
    } catch (_) {
      // Best effort only.
    }
  }

  /// True when the access token was rejected and a refresh may recover the
  /// session: HTTP 401 (current backend: `TOKEN_EXPIRED` / `UNAUTHENTICATED`)
  /// or the legacy 403 + `UNAUTHENTICATED` that older deployments returned
  /// for expired tokens. A 403 with any other code is a real permission
  /// denial (inactive account, wrong role) and is never retried.
  static bool _isAuthFailure(http.Response response) {
    if (response.statusCode == 401) return true;
    if (response.statusCode != 403) return false;
    try {
      final body = jsonDecode(response.body);
      return body is Map && body['code'] == 'UNAUTHENTICATED';
    } catch (_) {
      return false;
    }
  }

  /// Proactively refreshes the access token (used when the app resumes from
  /// the background so the first request after a long pause does not fail).
  /// Returns false when there is no refresh token or the refresh was rejected.
  Future<bool> refreshSessionIfPossible() async {
    if ((await _getRefreshToken())?.isNotEmpty != true) return false;
    return _refreshSession();
  }

  /// Uploads raw bytes (application/octet-stream) and returns the JSON data.
  /// Used by the file storage API, which avoids base64 overhead.
  Future<dynamic> sendBytes(String method, String endpoint, List<int> bytes,
      {Duration timeout = const Duration(seconds: 90)}) async {
    Future<http.Response> send() async {
      final headers = await _headers();
      headers['Content-Type'] = 'application/octet-stream';
      final uri = Uri.parse('$baseUrl$endpoint');
      return _send(
          method == 'PUT'
              ? http.put(uri, headers: headers, body: bytes)
              : http.post(uri, headers: headers, body: bytes),
          timeout: timeout);
    }

    var response = await send();
    if (_isAuthFailure(response) && await _refreshSession()) {
      response = await send();
    }
    return _handleResponse(response);
  }

  /// Downloads an authenticated binary resource (e.g. /files/:id/content).
  Future<Uint8List> getBytes(String endpoint,
      {Duration timeout = const Duration(seconds: 90)}) async {
    Future<http.Response> send() async {
      final headers = await _headers();
      headers['Accept'] = '*/*';
      return _send(http.get(Uri.parse('$baseUrl$endpoint'), headers: headers),
          timeout: timeout);
    }

    var response = await send();
    if (_isAuthFailure(response) && await _refreshSession()) {
      response = await send();
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    // Error bodies are JSON; reuse the standard error mapping.
    return _handleResponse(response) as Uint8List;
  }

  Future<bool> _refreshSession() async {
    final pending = _refreshInProgress;
    if (pending != null) return pending;
    final refresh = _refreshToken;
    final future = _refreshWithToken(refresh);
    _refreshInProgress = future;
    try {
      return await future;
    } finally {
      _refreshInProgress = null;
    }
  }

  String? _refreshToken;

  Future<bool> _refreshWithToken(String? currentRefresh) async {
    final token = currentRefresh ?? await _getRefreshToken();
    if (token == null || token.isEmpty) return false;
    try {
      final response = await _send(http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: await _headers(withAuth: false),
        body: jsonEncode({'refreshToken': token}),
      ));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Only a definitive rejection (revoked/expired/unknown refresh token)
        // ends the session. Server errors and rate limits are transient: keep
        // the tokens so the next request can retry the refresh.
        if (response.statusCode == 401 || response.statusCode == 403) {
          await clearTokens();
        }
        return false;
      }
      dynamic decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['data'] is Map) decoded = decoded['data'];
      if (decoded is! Map ||
          decoded['accessToken'] is! String ||
          decoded['refreshToken'] is! String) {
        await clearTokens();
        return false;
      }
      await setTokens(decoded['accessToken'], decoded['refreshToken']);
      _refreshToken = decoded['refreshToken'];
      return true;
    } catch (_) {
      return false;
    }
  }

  dynamic _handleResponse(http.Response response) {
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        throw ApiException(
          'The API returned an unexpected response (HTTP ${response.statusCode}).',
        );
      }
    } else {
      body = <String, dynamic>{};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body is Map ? (body['data'] ?? body) : body;
    }

    final msg = body is Map
        ? (body['message'] ??
            'API request failed (HTTP ${response.statusCode}).')
        : 'API request failed (HTTP ${response.statusCode}).';
    final code = body is Map ? body['code']?.toString() : null;
    throw ApiException(
      msg.toString(),
      statusCode: response.statusCode,
      code: code,
    );
  }
}
