import 'dart:typed_data';

import '../engine/ocr_engine.dart';
import '../models/ocr_capture.dart';
import 'pdf_rasterizer.dart';

/// Orchestrates an OCR capture end to end: expands PDFs to page images, runs
/// the platform OCR engine over every page, and returns per-page + combined
/// text. Platform-agnostic — the engine and rasteriser handle web vs mobile.
class OcrCaptureController {
  final OcrEngine _engine = createOcrEngine();

  bool supports(OcrLanguage language) => _engine.supports(language);

  /// Runs OCR over [documents]. [onProgress] reports (pagesDone, pagesTotal)
  /// so the UI can show a progress bar for multi-page jobs.
  Future<OcrCaptureResult> run(
    List<PickedDocument> documents, {
    OcrLanguage language = OcrLanguage.english,
    void Function(int done, int total)? onProgress,
  }) async {
    // 1) Flatten every document into a list of page images.
    final images = <Uint8List>[];
    for (final doc in documents) {
      if (doc.kind == OcrSourceKind.pdf) {
        images.addAll(await PdfRasterizer.toPageImages(doc.bytes));
      } else {
        images.add(doc.bytes);
      }
    }

    // 2) Recognise text page by page.
    final pages = <OcrPage>[];
    for (var i = 0; i < images.length; i++) {
      final text = await _engine.recognizeImage(images[i], language: language);
      pages.add(OcrPage(pageNumber: i + 1, text: text));
      onProgress?.call(i + 1, images.length);
    }
    return OcrCaptureResult(pages);
  }

  void dispose() => _engine.dispose();
}
