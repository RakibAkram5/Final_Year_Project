import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_engine.dart';

OcrEngine createPlatformOcrEngine() => _MlKitOcrEngine();

/// Mobile/desktop OCR via Google ML Kit's on-device text recognizer.
///
/// NOTE: ML Kit ships Latin, Chinese, Devanagari, Japanese and Korean script
/// recognizers — there is no Arabic/Urdu model, so Urdu is not supported here.
/// Urdu OCR is available on web (Tesseract.js). See [supports].
class _MlKitOcrEngine implements OcrEngine {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  bool supports(OcrLanguage language) => language == OcrLanguage.english;

  @override
  Future<String> recognizeImage(
    Uint8List imageBytes, {
    OcrLanguage language = OcrLanguage.english,
  }) async {
    // ML Kit's InputImage.fromFilePath is the most reliable path across image
    // formats, so persist the bytes to a short-lived temp file.
    final dir = await Directory.systemTemp.createTemp('ocr_');
    final file = File('${dir.path}/page.jpg');
    try {
      await file.writeAsBytes(imageBytes, flush: true);
      final input = InputImage.fromFilePath(file.path);
      final result = await _recognizer.processImage(input);
      return result.text.trim();
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {/* best-effort cleanup */}
    }
  }

  @override
  void dispose() => _recognizer.close();
}
