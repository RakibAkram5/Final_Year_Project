import '../remote/api_client.dart';

/// A class + section (e.g. "10th - A") is the single enrollment unit,
/// stored under the `class_sections` collection.
///
/// Students are enrolled here exactly once. Every subject offering (see
/// [ClassEntity] in `classes`) that shares the same academy_id + class_name
/// + section mirrors this roster instead of keeping its own independent
/// copy, so admins never re-enroll the same section per subject.
class ClassSectionEntity {
  final String id;
  final String academyId;
  final String className;
  final String program; // e.g. "FSC Pre-Engineering" — empty for 9th/10th
  final String section;
  final List<String> studentIds;
  final Map<String, String> studentNames;
  final Map<String, String> studentRollNumbers;
  final DateTime createdAt;

  const ClassSectionEntity({
    required this.id,
    required this.academyId,
    required this.className,
    this.program = '',
    required this.section,
    this.studentIds = const [],
    this.studentNames = const {},
    this.studentRollNumbers = const {},
    required this.createdAt,
  });

  int get enrollmentCount => studentIds.length;

  /// Display label like "10th - A" or "1st Year - Pre-Engineering - A".
  String get displayLabel {
    final buf = StringBuffer(className);
    if (program.isNotEmpty) buf.write(' - $program');
    if (section.isNotEmpty) buf.write(' - $section');
    return buf.toString();
  }

  Map<String, dynamic> toMap() => {
        'academy_id': academyId,
        'class_name': className,
        'program': program,
        'section': section,
        'student_ids': studentIds,
        'student_names': studentNames,
        'student_roll_numbers': studentRollNumbers,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ClassSectionEntity.fromMap(String id, Map<String, dynamic> map) {
    final rawIds = map['student_ids'];
    final rawNames = map['student_names'];
    final rawRolls = map['student_roll_numbers'];
    Map<String, String> asStringMap(dynamic raw) => raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
        : const {};
    return ClassSectionEntity(
      id: id,
      academyId: (map['academy_id'] ?? '').toString(),
      className: (map['class_name'] ?? '').toString(),
      program: (map['program'] ?? '').toString(),
      section: (map['section'] ?? '').toString(),
      studentIds: (rawIds is List)
          ? rawIds.map((e) => e.toString()).toList()
          : const [],
      studentNames: asStringMap(rawNames),
      studentRollNumbers: asStringMap(rawRolls),
      createdAt: ApiClient.parseDate(map['created_at']) ?? DateTime.now(),
    );
  }
}
