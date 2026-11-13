import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/models/app_user.dart';
import 'branding_utils.dart';

/// Shared white-label building blocks for every generated PDF: the academy's
/// own logo + identity in the header, consistent typography (bundled Noto
/// Sans so Urdu-script names and symbols render), and a discreet platform
/// attribution in the footer. TaleemPlus is never the document's identity.
class PdfBranding {
  PdfBranding._();

  static pw.ThemeData? _theme;

  /// Document theme with the bundled Noto Sans family (falls back to the
  /// built-in Helvetica when the assets are unavailable, e.g. in tests).
  static Future<pw.ThemeData> theme() async {
    if (_theme != null) return _theme!;
    try {
      final regular = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final bold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      final italic = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'));
      _theme = pw.ThemeData.withFont(
          base: regular, bold: bold, italic: italic, boldItalic: bold);
    } catch (e) {
      debugPrint('PDF font fallback (bundled Noto Sans unavailable): $e');
      _theme = pw.ThemeData.base();
    }
    return _theme!;
  }

  /// The academy logo as a PDF image: decodes stored data URIs locally and
  /// fetches legacy URLs. Null when no logo is set or it cannot be loaded.
  static Future<pw.ImageProvider?> loadLogo(String? logo) async {
    if (logo == null || logo.trim().isEmpty) return null;
    final bytes = BrandingUtils.decodeLogo(logo);
    if (bytes != null) {
      try {
        return pw.MemoryImage(bytes);
      } catch (e) {
        debugPrint('Academy logo could not be decoded for PDF: $e');
        return null;
      }
    }
    if (BrandingUtils.isNetworkUrl(logo)) {
      try {
        return await networkImage(logo.trim());
      } catch (e) {
        debugPrint('Academy logo could not be fetched for PDF: $e');
      }
    }
    return null;
  }

  /// Display name for documents: the academy's own name, never TaleemPlus.
  static String academyName(AppUser? academy) {
    final name = academy?.academyName?.trim();
    return (name == null || name.isEmpty) ? 'Academy' : name;
  }

  /// Contact line (address · phone · email) with only the fields that exist.
  static List<String> contactLines(AppUser? academy) {
    final lines = <String>[];
    final address = academy?.academyAddress?.trim();
    if (address != null && address.isNotEmpty) lines.add(address);
    final contact = [
      if ((academy?.academyPhone ?? '').trim().isNotEmpty)
        'Phone: ${academy!.academyPhone!.trim()}',
      if ((academy?.academyEmail ?? '').trim().isNotEmpty)
        'Email: ${academy!.academyEmail!.trim()}',
    ].join('   ·   ');
    if (contact.isNotEmpty) lines.add(contact);
    return lines;
  }

  static const PdfColor brand = PdfColor.fromInt(0xFF0B5F5B);
  static const PdfColor brandLight = PdfColor.fromInt(0xFFE3F4F3);
  static const PdfColor ink = PdfColor.fromInt(0xFF111827);
  static const PdfColor muted = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor line = PdfColor.fromInt(0xFFD1D5DB);

  /// Letterhead: logo (or initials monogram) + academy identity on the left,
  /// an optional document title block on the right.
  static pw.Widget letterhead(AppUser? academy, pw.ImageProvider? logo,
      {String? title, List<String> meta = const []}) {
    final name = academyName(academy);
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: brand, width: 1.6))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _logoBox(logo, name),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(name.toUpperCase(),
                    style: const pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: brand,
                        letterSpacing: 0.6)),
                for (final line in contactLines(academy))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 1.5),
                    child: pw.Text(line,
                        style: const pw.TextStyle(fontSize: 8.5, color: muted)),
                  ),
              ],
            ),
          ),
          if (title != null) ...[
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(title,
                    style: const pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                        letterSpacing: 1)),
                for (final m in meta)
                  pw.Text(m,
                      style: const pw.TextStyle(fontSize: 8.5, color: muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _logoBox(pw.ImageProvider? logo, String name) {
    const double size = 48;
    if (logo != null) {
      return pw.Container(
        width: size,
        height: size,
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: line, width: 0.6),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
        padding: const pw.EdgeInsets.all(3),
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      );
    }
    return pw.Container(
      width: size,
      height: size,
      alignment: pw.Alignment.center,
      decoration: const pw.BoxDecoration(
          color: brandLight,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Text(BrandingUtils.initials(name),
          style: const pw.TextStyle(
              fontSize: 16, fontWeight: pw.FontWeight.bold, color: brand)),
    );
  }

  /// Page footer: academy name on the left, page numbers on the right, and a
  /// small platform attribution — the only place TaleemPlus appears.
  static pw.Widget footer(pw.Context context, AppUser? academy,
      {String? note}) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: line, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
                note ?? '${academyName(academy)} · Generated with TaleemPlus',
                style: const pw.TextStyle(fontSize: 7.5, color: muted)),
          ),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: muted)),
        ],
      ),
    );
  }
}
