import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ocr_capture.dart';

/// Cross-platform document selection for OCR. Works on web and mobile by always
/// reading the bytes into memory (file_picker `withData: true`), so downstream
/// code never touches dart:io paths.
class DocumentPicker {
  final ImagePicker _imagePicker = ImagePicker();

  static const List<String> allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  /// Lets the user pick one or more PDFs / images from their device.
  /// file_picker 13.x selects multiple by default and returns the files
  /// directly; `readAsBytes()` works on web and mobile alike.
  Future<List<PickedDocument>> pickDocuments() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    final docs = <PickedDocument>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      docs.add(PickedDocument(
        name: f.name,
        bytes: bytes,
        kind: PickedDocument.kindFromName(f.name),
      ));
    }
    return docs;
  }

  /// Captures a single image from the camera (mobile) or a file dialog (web).
  Future<PickedDocument?> captureFromCamera() async {
    final XFile? shot = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    if (shot == null) return null;
    final bytes = await shot.readAsBytes();
    return PickedDocument(
      name: shot.name,
      bytes: bytes,
      kind: OcrSourceKind.image,
    );
  }
}
