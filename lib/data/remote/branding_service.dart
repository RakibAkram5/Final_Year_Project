import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/branding/branding_utils.dart';
import 'api_client.dart';

/// Academy branding (white-label identity) as stored by the backend.
class AcademyBranding {
  final String academyId;
  final String? academyCode;
  final String name;
  final String? address;
  final String? phone;
  final String? email;

  /// Data URI (stored image) or legacy URL; null when no logo is set.
  final String? logo;
  final bool hasCustomLogo;
  final DateTime? logoUpdatedAt;

  const AcademyBranding({
    required this.academyId,
    required this.name,
    this.academyCode,
    this.address,
    this.phone,
    this.email,
    this.logo,
    this.hasCustomLogo = false,
    this.logoUpdatedAt,
  });

  factory AcademyBranding.fromJson(Map<String, dynamic> json) =>
      AcademyBranding(
        academyId: (json['academyId'] ?? '').toString(),
        academyCode: json['academyCode']?.toString(),
        name: (json['name'] ?? '').toString(),
        address: json['address']?.toString(),
        phone: json['phone']?.toString(),
        email: json['email']?.toString(),
        logo: json['logo']?.toString(),
        hasCustomLogo: json['hasCustomLogo'] == true,
        logoUpdatedAt: ApiClient.parseDate(json['logoUpdatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'academyId': academyId,
        'academyCode': academyCode,
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        'logo': logo,
        'hasCustomLogo': hasCustomLogo,
        'logoUpdatedAt': logoUpdatedAt?.toUtc().toIso8601String(),
      };
}

/// Public identity shown on the login screen (name + logo only).
class PublicBranding {
  final String academyCode;
  final String name;
  final String? logo;
  const PublicBranding(
      {required this.academyCode, required this.name, this.logo});

  Map<String, dynamic> toJson() =>
      {'academyCode': academyCode, 'name': name, 'logo': logo};

  factory PublicBranding.fromJson(Map<String, dynamic> json) => PublicBranding(
        academyCode: (json['academyCode'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        logo: json['logo']?.toString(),
      );
}

class BrandingService {
  final ApiClient _api;
  BrandingService({ApiClient? api}) : _api = api ?? ApiClient();

  /// Client-side caps mirror the server (which enforces them regardless).
  static const int maxLogoBytes = 300 * 1024;
  static const int maxLogoDimension = 1024;
  static const String lastBrandingKey = 'tp_last_academy_branding';

  Future<AcademyBranding> getBranding() async {
    final res = await _api.get('/academy/branding');
    return AcademyBranding.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<AcademyBranding> saveBranding({
    String? name,
    String? address,
    String? phone,
    String? email,
    Uint8List? logoBytes,
    String? logoMimeType,
    bool removeLogo = false,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (removeLogo) 'removeLogo': true,
      if (!removeLogo && logoBytes != null) ...{
        'logoBase64': base64Encode(logoBytes),
        'logoMimeType': logoMimeType ?? 'image/png',
      },
    };
    final res = await _api.put('/academy/branding', body);
    final branding =
        AcademyBranding.fromJson(Map<String, dynamic>.from(res as Map));
    await rememberForLogin(PublicBranding(
        academyCode: branding.academyCode ?? '',
        name: branding.name,
        logo: branding.logo));
    return branding;
  }

  /// Unauthenticated identity lookup by academy code (login screen).
  Future<PublicBranding> lookupPublic(String code) async {
    final res = await _api.get(
        '/academy/branding/public?code=${Uri.encodeQueryComponent(code.trim())}',
        withAuth: false);
    return PublicBranding.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Caches the last signed-in academy's identity so the login screen can
  /// show it before any session exists (and after a restart).
  static Future<void> rememberForLogin(PublicBranding branding) async {
    if (branding.name.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastBrandingKey, jsonEncode(branding.toJson()));
  }

  static Future<PublicBranding?> lastKnown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(lastBrandingKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final branding = PublicBranding.fromJson(Map<String, dynamic>.from(json));
      return branding.name.isEmpty ? null : branding;
    } catch (_) {
      return null;
    }
  }

  static Future<void> forgetLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(lastBrandingKey);
  }

  /// Whether [bytes] look like a supported image (magic bytes) — the same
  /// check the server performs, done early for a clear client message.
  static String? detectMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  static bool looksLikeDataUri(String? value) => BrandingUtils.isDataUri(value);
}
