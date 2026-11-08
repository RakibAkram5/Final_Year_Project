class StudentQuery {
  final String id;
  final String academyId;
  final String classId;
  final String studentId;
  final String studentName;
  final String teacherId;
  final String question;
  final String? answer;
  final bool isResolved;
  final DateTime createdAt;
  final DateTime? answeredAt;

  StudentQuery({
    required this.id,
    required this.academyId,
    required this.classId,
    required this.studentId,
    required this.studentName,
    required this.teacherId,
    required this.question,
    this.answer,
    this.isResolved = false,
    required this.createdAt,
    this.answeredAt,
  });

  Map<String, dynamic> toMap() => {
        'academy_id': academyId,
        'class_id': classId,
        'student_id': studentId,
        'student_name': studentName,
        'teacher_id': teacherId,
        'question': question.trim(),
        'answer': answer,
        'is_resolved': isResolved,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'answered_at': answeredAt?.toUtc().toIso8601String(),
      };

  static DateTime _parseDate(dynamic val, [DateTime? fallback]) {
    if (val == null) return fallback ?? DateTime.now();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return fallback ?? DateTime.now();
  }

  factory StudentQuery.fromMap(String id, Map<String, dynamic> map) {
    final rawCreatedAt = map['created_at'] ?? map['createdAt'];
    final rawAnsweredAt = map['answered_at'] ?? map['answeredAt'];

    return StudentQuery(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: (map['academy_id'] ?? map['academyId'] ?? '').toString(),
      classId: (map['class_id'] ?? map['classId'] ?? '').toString(),
      studentId: (map['student_id'] ?? map['studentId'] ?? '').toString(),
      studentName:
          (map['student_name'] ?? map['studentName'] ?? 'Student').toString(),
      teacherId: (map['teacher_id'] ?? map['teacherId'] ?? '').toString(),
      question: (map['question'] ?? '').toString(),
      answer: map['answer'],
      isResolved: map['is_resolved'] ?? map['isResolved'] ?? false,
      createdAt: _parseDate(rawCreatedAt),
      answeredAt: rawAnsweredAt != null ? _parseDate(rawAnsweredAt) : null,
    );
  }
}
