import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'live_query.dart';

/// What an uploaded file belongs to. Mirrors the backend's categories.
enum FileCategory {
  courseMaterial('COURSE_MATERIAL'),
  assignmentInstruction('ASSIGNMENT_INSTRUCTION'),
  assignmentSubmission('ASSIGNMENT_SUBMISSION'),
  examDocument('EXAM_DOCUMENT'),
  studentDocument('STUDENT_DOCUMENT'),
  teacherDocument('TEACHER_DOCUMENT');

  final String api;
  const FileCategory(this.api);

  /// Extensions the server accepts for this category.
  List<String> get allowedExtensions => this == assignmentSubmission
      ? const ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg']
      : const [
          'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', //
          'png', 'jpg', 'jpeg', 'txt'
        ];
}

/// Metadata of a stored file. The bytes are only reachable through the
/// authenticated `/files/:id/content` endpoint.
class StoredFile {
  final String id;
  final String category;
  final String ownerId;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final String? description;
  final String? uploadedByName;
  final DateTime createdAt;

  const StoredFile({
    required this.id,
    required this.category,
    required this.ownerId,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.description,
    this.uploadedByName,
  });

  factory StoredFile.fromJson(Map<String, dynamic> j) => StoredFile(
        id: j['id'].toString(),
        category: (j['category'] ?? '').toString(),
        ownerId: (j['ownerId'] ?? '').toString(),
        originalName: (j['originalName'] ?? 'file').toString(),
        mimeType: (j['mimeType'] ?? 'application/octet-stream').toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        description: j['description']?.toString(),
        uploadedByName: j['uploadedByName']?.toString(),
        createdAt: ApiClient.parseDateOr(j['createdAt'], DateTime.now()),
      );

  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage => mimeType.startsWith('image/');

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class FileService {
  final ApiClient _api;
  FileService({ApiClient? api}) : _api = api ?? ApiClient();

  /// Server-side upload limit (Vercel request bodies are capped at 4.5 MB).
  static const int maxUploadBytes = 4 * 1024 * 1024;

  static String topic(FileCategory c, String ownerId) =>
      'files:${c.api}:$ownerId';

  Future<List<StoredFile>> list(FileCategory category, String ownerId) async {
    final res = await _api.get(
        '/files?category=${category.api}&ownerId=${Uri.encodeComponent(ownerId)}');
    return (res as List)
        .map((e) => StoredFile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Stream<List<StoredFile>> watch(FileCategory category, String ownerId) =>
      liveQuery(topic(category, ownerId), () => list(category, ownerId));

  void _checkSize(List<int> bytes) {
    if (bytes.isEmpty) throw ApiException('The selected file is empty.');
    if (bytes.length > maxUploadBytes) {
      throw ApiException('Files must be 4 MB or smaller.');
    }
  }

  Future<StoredFile> upload({
    required FileCategory category,
    required String ownerId,
    required String filename,
    required Uint8List bytes,
    String? description,
  }) async {
    _checkSize(bytes);
    final query = [
      'category=${category.api}',
      'ownerId=${Uri.encodeComponent(ownerId)}',
      'filename=${Uri.encodeComponent(filename)}',
      if (description != null && description.trim().isNotEmpty)
        'description=${Uri.encodeComponent(description.trim())}',
    ].join('&');
    final res = await _api.sendBytes('POST', '/files?$query', bytes);
    DataChanges.notify(topic(category, ownerId));
    return StoredFile.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<StoredFile> replace(StoredFile file,
      {required String filename, required Uint8List bytes}) async {
    _checkSize(bytes);
    final res = await _api.sendBytes(
        'PUT',
        '/files/${file.id}/content?filename=${Uri.encodeComponent(filename)}',
        bytes);
    DataChanges.notify('files:${file.category}:${file.ownerId}');
    return StoredFile.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> delete(StoredFile file) async {
    await _api.delete('/files/${file.id}');
    DataChanges.notify('files:${file.category}:${file.ownerId}');
  }

  Future<Uint8List> download(StoredFile file) =>
      _api.getBytes('/files/${file.id}/content');
}
