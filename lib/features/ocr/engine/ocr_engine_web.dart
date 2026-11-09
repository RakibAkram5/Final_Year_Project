import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'ocr_engine.dart';

OcrEngine createPlatformOcrEngine() => _TesseractOcrEngine();

// --- Tesseract.js bindings (loaded from a CDN at first use) ----------------
const _tesseractCdn =
    'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';

@JS('Tesseract')
external JSAny? get _tesseractGlobal;

// Tesseract.recognize(image, lang) -> Promise<{ data: { text } }>
@JS('Tesseract.recognize')
external JSPromise<JSObject> _recognize(JSString image, JSString lang);

/// Web OCR via Tesseract.js. Supports English and Urdu (and the combination),
/// which ML Kit on mobile cannot do. The script is injected once, lazily.
class _TesseractOcrEngine implements OcrEngine {
  Future<void>? _loading;

  @override
  bool supports(OcrLanguage language) => true;

  Future<void> _ensureLoaded() {
    if (_tesseractGlobal != null) return Future<void>.value();
    return _loading ??= _injectScript();
  }

  Future<void> _injectScript() {
    final completer = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = _tesseractCdn
      ..async = true;
    script.onload = ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    script.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
            StateError('Failed to load the OCR engine (Tesseract.js).'));
      }
    }).toJS;
    web.document.head!.appendChild(script);
    return completer.future;
  }

  String _dataUrl(Uint8List bytes) {
    // Browsers decode a data URL by its declared MIME, so sniff PNG vs JPEG.
    final isPng = bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final mime = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  @override
  Future<String> recognizeImage(
    Uint8List imageBytes, {
    OcrLanguage language = OcrLanguage.english,
  }) async {
    await _ensureLoaded();
    final result = await _recognize(
      _dataUrl(imageBytes).toJS,
      language.tesseractCode.toJS,
    ).toDart;
    final data = result.getProperty<JSObject>('data'.toJS);
    final text = data.getProperty<JSString>('text'.toJS);
    return text.toDart.trim();
  }

  @override
  void dispose() {/* nothing persistent to release */}
}
