import '../../../data/remote/api_client.dart';
import '../../../data/remote/live_query.dart';
import '../models/ocr_document_model.dart';

/// Persists OCR scans through the REST API (`/ocr`). The class name is kept
/// for compatibility with existing screens; it no longer uses Firestore.
///
/// Text extraction itself stays on-device (Google ML Kit); only the
/// resulting text is stored, scoped to the signed-in user and academy.
class OcrFirestoreService {
  final ApiClient _api = ApiClient();

  OcrDocumentModel _parse(Map item) => OcrDocumentModel.fromMap(
      Map<String, dynamic>.from(item), (item['id'] ?? '').toString());

  /// Saves a new scanned document and returns the stored copy.
  Future<OcrDocumentModel> saveDocument({
    required String title,
    required String extractedText,
    required String createdByUid,
    required String createdByName,
  }) async {
    final res = await _api.post('/ocr', {
      'title': title.trim(),
      'extractedText': extractedText.trim(),
    });
    DataChanges.notify(DataTopics.ocrDocuments);
    return _parse(res as Map);
  }

  Future<List<OcrDocumentModel>> fetchDocuments() async {
    final res = await _api.get('/ocr');
    final list = (res as List).map((item) => _parse(item as Map)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// The signed-in user's scan history (latest first). Errors are emitted
  /// on the stream so the history screen can show them.
  Stream<List<OcrDocumentModel>> getDocuments(String uid) =>
      liveQuery(DataTopics.ocrDocuments, fetchDocuments);

  Future<void> deleteDocument(String documentId) async {
    await _api.delete('/ocr/$documentId');
    DataChanges.notify(DataTopics.ocrDocuments);
  }

  Future<void> updateDocument({
    required String documentId,
    required String title,
    required String extractedText,
  }) async {
    await _api.put('/ocr/$documentId', {
      'title': title.trim(),
      'extractedText': extractedText.trim(),
    });
    DataChanges.notify(DataTopics.ocrDocuments);
  }

  /// Returns the document, or null if it does not exist for this user.
  Future<OcrDocumentModel?> getDocumentById(String documentId) async {
    try {
      final res = await _api.get('/ocr/$documentId');
      return res is Map ? _parse(res) : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
