class SharedResource {
  final String id;
  final String academyId;
  final String classId;
  final String teacherId;
  final String teacherName;
  final String title;
  final String description;
  final String? fileUrl;

  /// Full text body (e.g. a published OCR scan); up to 50k characters.
  final String contentText;
  final DateTime createdAt;

  SharedResource({
    required this.id,
    required this.academyId,
    required this.classId,
    required this.teacherId,
    required this.teacherName,
    required this.title,
    required this.description,
    this.fileUrl,
    this.contentText = '',
    required this.createdAt,
  });

  /// Request body for `POST /resources` (camelCase, matching the server's
  /// validator). A resource needs either a file URL or text content.
  Map<String, dynamic> toApiBody() => {
        'classId': classId,
        'title': title.trim(),
        if (description.trim().isNotEmpty)
          'description': description.trim().length > 2000
              ? description.trim().substring(0, 2000)
              : description.trim(),
        if (fileUrl != null && fileUrl!.trim().isNotEmpty)
          'fileUrl': fileUrl!.trim(),
        if (contentText.trim().isNotEmpty) 'contentText': contentText.trim(),
      };

  Map<String, dynamic> toMap() => {
        'academy_id': academyId,
        'class_id': classId,
        'teacher_id': teacherId,
        'teacher_name': teacherName,
        'title': title.trim(),
        'description': description.trim(),
        'file_url': fileUrl,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return DateTime.now();
  }

  factory SharedResource.fromMap(String id, Map<String, dynamic> map) {
    final rawCreatedAt = map['created_at'] ?? map['createdAt'];

    return SharedResource(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: (map['academy_id'] ?? map['academyId'] ?? '').toString(),
      classId: (map['class_id'] ?? map['classId'] ?? '').toString(),
      teacherId: (map['teacher_id'] ?? map['teacherId'] ?? '').toString(),
      teacherName:
          (map['teacher_name'] ?? map['teacherName'] ?? 'Teacher').toString(),
      title: (map['title'] ?? '').toString(),
      // Text-only resources (e.g. OCR scans) carry their body in
      // content_text; show it wherever the description is displayed.
      description: (map['description'] ?? '').toString().isNotEmpty
          ? map['description'].toString()
          : (map['content_text'] ?? map['contentText'] ?? '').toString(),
      fileUrl: (map['file_url'] ?? map['fileUrl'])?.toString(),
      contentText: (map['content_text'] ?? map['contentText'] ?? '').toString(),
      createdAt: _parseDate(rawCreatedAt),
    );
  }
}
