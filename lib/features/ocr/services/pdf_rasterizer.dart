import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Rasterises PDF pages to PNG images so the OCR engine (which only reads
/// images) can process multi-page PDFs. Uses the `printing` package, which
/// works on both web and mobile.
class PdfRasterizer {
  /// Returns one PNG per page of [pdfBytes]. [dpi] trades accuracy for speed
  /// and memory; 200 is a good default for document OCR.
  static Future<List<Uint8List>> toPageImages(
    Uint8List pdfBytes, {
    double dpi = 200,
  }) async {
    final images = <Uint8List>[];
    await for (final page in Printing.raster(pdfBytes, dpi: dpi)) {
      images.add(await page.toPng());
    }
    return images;
  }
}
