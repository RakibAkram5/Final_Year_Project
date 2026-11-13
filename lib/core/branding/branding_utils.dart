import 'dart:convert';
import 'dart:typed_data';

/// Helpers for academy logos, which the backend serves either as a base64
/// data URI (stored image) or, for legacy rows, as an http(s) URL.
///
/// Pure Dart (no Flutter imports) so the PDF services and widgets share it.
class BrandingUtils {
  BrandingUtils._();

  static final _dataUri = RegExp(r'^data:(image/[a-z0-9.+-]+);base64,(.*)$',
      caseSensitive: false, dotAll: true);

  static bool isDataUri(String? value) =>
      value != null && _dataUri.hasMatch(value.trim());

  static bool isNetworkUrl(String? value) {
    if (value == null) return false;
    final uri = Uri.tryParse(value.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Decoded image bytes for a data-URI (or bare base64) logo; null for
  /// URLs, empty values or malformed data.
  static Uint8List? decodeLogo(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty || isNetworkUrl(text)) return null;
    final match = _dataUri.firstMatch(text);
    final payload = (match?.group(2) ?? text).replaceAll(RegExp(r'\s'), '');
    try {
      final bytes = base64Decode(payload);
      return bytes.isEmpty ? null : bytes;
    } on FormatException {
      return null;
    }
  }

  /// MIME type declared by a data URI, or null.
  static String? mimeTypeOf(String? value) =>
      value == null ? null : _dataUri.firstMatch(value.trim())?.group(1);

  /// Builds the data URI the backend expects for an upload.
  static String toDataUri(Uint8List bytes, String mimeType) =>
      'data:$mimeType;base64,${base64Encode(bytes)}';

  /// Initials used for the neutral placeholder when no logo is set.
  static String initials(String? name, {String fallback = 'A'}) {
    final words = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return fallback;
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? fallback : letters;
  }
}
