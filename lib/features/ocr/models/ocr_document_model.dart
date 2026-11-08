class OcrDocumentModel {
  final String id;
  final String title;
  final String extractedText;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;

  OcrDocumentModel({
    required this.id,
    required this.title,
    required this.extractedText,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
  });

  // Firestore se data map mein convert karne ke liye helper
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

  factory OcrDocumentModel.fromMap(
      Map<String, dynamic> map, String documentId) {
    final rawTs = map['created_at'] ?? map['createdAt'];
    return OcrDocumentModel(
      id: documentId.isNotEmpty ? documentId : (map['id'] ?? '').toString(),
      title: map['title'] ?? '',
      extractedText: map['extracted_text'] ?? map['extractedText'] ?? '',
      createdByUid: map['created_by_uid'] ?? map['createdById'] ?? '',
      createdByName: map['created_by_name'] ?? map['createdByName'] ?? '',
      createdAt: _parseDate(rawTs),
    );
  }

  // Firestore mein data save karne ke liye map return karega
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'extracted_text': extractedText,
      'created_by_uid': createdByUid,
      'created_by_name': createdByName,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // Edit karne ke liye copyWith method
  OcrDocumentModel copyWith({
    String? title,
    String? extractedText,
  }) {
    return OcrDocumentModel(
      id: id,
      title: title ?? this.title,
      extractedText: extractedText ?? this.extractedText,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: createdAt,
    );
  }
}
