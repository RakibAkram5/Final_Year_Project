import '../remote/api_client.dart';

/// One attendance record: a single student on a single date
/// (`/attendance`, unique per class + student + day on the server).
class AttendanceRecord {
  final String id;
  final String academyId; // NEW
  final String classId;
  final String studentId;
  final String studentName;
  final DateTime logDate;
  final String status; // 'present' | 'absent' | 'late' | 'leave'
  final String markedByUid;
  final DateTime recordedAt;

  const AttendanceRecord({
    required this.id,
    required this.academyId, // NEW
    required this.classId,
    required this.studentId,
    required this.studentName,
    required this.logDate,
    required this.status,
    required this.markedByUid,
    required this.recordedAt,
  });

  bool get isPresent => status == 'present';
  bool get isAbsent => status == 'absent';
  bool get isLate => status == 'late';
  bool get isLeave => status == 'leave';

  /// Deterministic Firestore doc id so that saving the same
  /// (class, student, date) upserts instead of duplicating.
  static String buildId({
    required String classId,
    required String studentId,
    required DateTime date,
  }) {
    final key = _dateOnly(date);
    return '${classId}_${studentId}_$key';
  }

  Map<String, dynamic> toMap() => {
        'academy_id': academyId,
        'class_id': classId,
        'student_id': studentId,
        'student_name': studentName,
        'log_date': _dateOnly(logDate),
        'status': status,
        'marked_by_uid': markedByUid,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
      };

  factory AttendanceRecord.fromMap(String id, Map<String, dynamic> map) {
    // log_date is a calendar day ("YYYY-MM-DD"); parse it as a local date
    // so it is never shifted across midnight by a time-zone conversion.
    final rawDay = (map['log_date'] ?? '').toString();
    final dayMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(rawDay);
    if (dayMatch == null) {
      throw FormatException('Attendance record $id has an invalid log_date.');
    }
    final logDate = DateTime(int.parse(dayMatch.group(1)!),
        int.parse(dayMatch.group(2)!), int.parse(dayMatch.group(3)!));
    return AttendanceRecord(
      id: id,
      academyId: (map['academy_id'] ?? '').toString(),
      classId: (map['class_id'] ?? '').toString(),
      studentId: (map['student_id'] ?? '').toString(),
      studentName: (map['student_name'] ?? '').toString(),
      logDate: logDate,
      status: (map['status'] ?? 'absent').toString().toLowerCase(),
      markedByUid: (map['marked_by_uid'] ?? '').toString(),
      recordedAt: ApiClient.parseDate(map['recorded_at']) ?? logDate,
    );
  }

  static String _dateOnly(DateTime d) {
    final iso = DateTime(d.year, d.month, d.day).toIso8601String();
    return iso.substring(0, 10);
  }
}
