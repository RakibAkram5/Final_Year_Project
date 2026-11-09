import 'dart:typed_data';

// Platform-selected OCR engine factory. On mobile (dart:io) we use Google
// ML Kit; on web (js_interop) we use Tesseract.js. The stub throws so a new
// platform fails loudly instead of silently doing nothing.
import 'ocr_engine_stub.dart'
    if (dart.library.io) 'ocr_engine_io.dart'
    if (dart.library.js_interop) 'ocr_engine_web.dart';

/// OCR languages the app offers. Urdu is only honoured by engines that support
/// its script (Tesseract.js on web); ML Kit's Latin recognizer ignores it.
enum OcrLanguage {
  english,
  urdu,
  englishAndUrdu;

  /// Tesseract language code(s), e.g. "eng", "urd", "eng+urd".
  String get tesseractCode {
    switch (this) {
      case OcrLanguage.english:
        return 'eng';
      case OcrLanguage.urdu:
        return 'urd';
      case OcrLanguage.englishAndUrdu:
        return 'eng+urd';
    }
  }

  String get label {
    switch (this) {
      case OcrLanguage.english:
        return 'English';
      case OcrLanguage.urdu:
        return 'Urdu';
      case OcrLanguage.englishAndUrdu:
        return 'English + Urdu';
    }
  }
}

/// Recognised text for a single page/image.
class OcrPageResult {
  final int pageNumber; // 1-based
  final String text;
  const OcrPageResult({required this.pageNumber, required this.text});
}

/// A platform OCR engine. Implementations recognise text from raw image bytes
/// (PNG/JPEG). PDF pages are rasterised to images before reaching the engine
/// (see PdfRasterizer), so the engine only ever deals with images.
abstract class OcrEngine {
  /// Recognises text in a single image. [language] is a hint; engines that do
  /// not support a script fall back to what they can read.
  Future<String> recognizeImage(
    Uint8List imageBytes, {
    OcrLanguage language = OcrLanguage.english,
  });

  /// Whether this engine can actually read [language]. The UI uses this to warn
  /// (e.g. ML Kit on mobile cannot read Urdu).
  bool supports(OcrLanguage language);

  /// Releases native resources. Safe to call more than once.
  void dispose();
}

/// Returns the OCR engine for the current platform (ML Kit on mobile,
/// Tesseract.js on web). Implemented per-platform via the conditional import.
OcrEngine createOcrEngine() => createPlatformOcrEngine();
