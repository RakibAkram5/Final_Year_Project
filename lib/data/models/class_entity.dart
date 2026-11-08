import '../remote/api_client.dart';

/// A class/section stored in Firestore under the `classes` collection.
///
/// Enrollment is embedded in the class document:
///   - studentIds   : list of Firebase uids of enrolled students
///   - studentNames : {uid: displayName} for quick rendering
class ClassEntity {
  final String id;
  final String academyId; // NEW
  final String className;
  final String section;
  final String subject;
  final String primaryTeacherId; // teacher's Firebase uid
  final String primaryTeacherName;
  final String primaryTeacherEmail;
  final List<String> studentIds;
  final Map<String, String> studentNames;
  final DateTime createdAt;

  const ClassEntity({
    required this.id,
    required this.academyId, // NEW
    required this.className,
    this.section = '',
    this.subject = '',
    this.primaryTeacherId = '',
    this.primaryTeacherName = '',
    this.primaryTeacherEmail = '',
    this.studentIds = const [],
    this.studentNames = const {},
    required this.createdAt,
  });

  int get enrollmentCount => studentIds.length;

  /// Display label like "Class 10 - A (Physics)"
  String get displayLabel {
    final buf = StringBuffer(className);
    if (section.isNotEmpty) buf.write(' - $section');
    if (subject.isNotEmpty) buf.write(' ($subject)');
    return buf.toString();
  }

  Map<String, dynamic> toMap() => {
        'academy_id': academyId,
        'class_name': className,
        'section': section,
        'subject': subject,
        'primary_teacher_id': primaryTeacherId,
        'primary_teacher_name': primaryTeacherName,
        'primary_teacher_email': primaryTeacherEmail,
        'student_ids': studentIds,
        'student_names': studentNames,
        'created_at': createdAt.millisecondsSinceEpoch == 0
            ? DateTime.now().toUtc().toIso8601String()
            : createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory ClassEntity.fromMap(String id, Map<String, dynamic> map) {
    final rawIds = map['student_ids'];
    final rawNames = map['student_names'];
    final ts = map['created_at'];
    return ClassEntity(
      id: id,
      academyId: (map['academy_id'] ?? '') as String,
      className: (map['class_name'] ?? '') as String,
      section: (map['section'] ?? '') as String,
      subject: (map['subject'] ?? '') as String,
      primaryTeacherId: (map['primary_teacher_id'] ?? '') as String,
      primaryTeacherName: (map['primary_teacher_name'] ?? '') as String,
      primaryTeacherEmail: (map['primary_teacher_email'] ?? '') as String,
      studentIds: (rawIds is List)
          ? rawIds.map((e) => e.toString()).toList()
          : const [],
      studentNames: (rawNames is Map)
          ? rawNames.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
          : const {},
      createdAt: ApiClient.parseDate(ts) ?? DateTime.now(),
    );
  }
}
