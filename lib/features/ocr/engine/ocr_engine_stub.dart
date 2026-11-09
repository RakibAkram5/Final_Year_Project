import 'ocr_engine.dart';

/// Fallback for platforms that are neither dart:io nor web. Never selected in
/// a normal Flutter build; present so the conditional import always resolves.
OcrEngine createPlatformOcrEngine() =>
    throw UnsupportedError('OCR is not supported on this platform.');
