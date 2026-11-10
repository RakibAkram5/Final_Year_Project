import 'dart:typed_data';

/// What kind of source the user picked.
enum OcrSourceKind { image, pdf }

/// A document the user selected (an image or a PDF), held in memory so the same
/// code path works on web and mobile.
class PickedDocument {
  final String name;
  final Uint8List bytes;
  final OcrSourceKind kind;

  const PickedDocument({
    required this.name,
    required this.bytes,
    required this.kind,
  });

  static OcrSourceKind kindFromName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.pdf') ? OcrSourceKind.pdf : OcrSourceKind.image;
  }
}

/// The result of running OCR over one or more documents: the per-page text plus
/// a combined document the user can preview and edit before saving.
class OcrCaptureResult {
  final List<OcrPage> pages;

  const OcrCaptureResult(this.pages);

  bool get isEmpty => pages.every((p) => p.text.trim().isEmpty);

  /// Pages joined with a form-feed separator, ready for the editor.
  String get combinedText => pages
      .map((p) => p.text.trim())
      .where((t) => t.isNotEmpty)
      .join('\n\n--- Page break ---\n\n');
}

class OcrPage {
  final int pageNumber; // 1-based across the whole capture
  final String text;
  const OcrPage({required this.pageNumber, required this.text});
}
