class TestMarkModel {
  final String id; // {quizId}_{studentUid}
  final String academyId; // NEW
  final String quizId;
  final String studentId;
  final String studentName;
  final String classId;
  final String subject; // NEW: Denormalized for AI
  final String month; // NEW: Denormalized for AI
  final double marksObtained;
  final double totalMarks;
  final double percentage;
  final String gradeLetter;
  final String? teacherFeedback;
  final DateTime updatedAt;

  TestMarkModel({
    required this.id,
    required this.academyId, // NEW
    required this.quizId,
    required this.studentId,
    required this.studentName,
    required this.classId,
    required this.subject,
    required this.month,
    required this.marksObtained,
    required this.totalMarks,
    required this.percentage,
    required this.gradeLetter,
    this.teacherFeedback,
    required this.updatedAt,
  });

  // Grade calculation logic
  static String calculateGrade(double percentage) {
    if (percentage >= 90) return 'A+';
    if (percentage >= 80) return 'A';
    if (percentage >= 70) return 'B';
    if (percentage >= 60) return 'C';
    if (percentage >= 50) return 'D';
    return 'F';
  }

  Map<String, dynamic> toMap() {
    return {
      'academy_id': academyId, // NEW
      'quiz_id': quizId,
      'student_id': studentId,
      'student_name': studentName,
      'class_id': classId,
      'subject': subject,
      'month': month,
      'marks_obtained': marksObtained,
      'total_marks': totalMarks,
      'percentage': percentage,
      'grade_letter': gradeLetter,
      'teacher_feedback': teacherFeedback,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

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

  factory TestMarkModel.fromMap(String id, Map<String, dynamic> map) {
    final rawUpdated = map['updated_at'] ?? map['updatedAt'];

    return TestMarkModel(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: (map['academy_id'] ?? map['academyId'] ?? '').toString(),
      quizId: (map['quiz_id'] ?? map['quizId'] ?? '').toString(),
      studentId: (map['student_id'] ?? map['studentId'] ?? '').toString(),
      studentName: (map['student_name'] ?? map['studentName'] ?? '').toString(),
      classId: (map['class_id'] ?? map['classId'] ?? '').toString(),
      subject: (map['subject'] ?? 'General').toString(),
      month: (map['month'] ?? '').toString(),
      marksObtained:
          ((map['marks_obtained'] ?? map['marksObtained']) ?? 0).toDouble(),
      totalMarks: ((map['total_marks'] ?? map['totalMarks']) ?? 0).toDouble(),
      percentage: ((map['percentage'] ?? map['percentage']) ?? 0).toDouble(),
      gradeLetter:
          (map['grade_letter'] ?? map['gradeLetter'] ?? 'F').toString(),
      teacherFeedback: map['teacher_feedback'] ?? map['teacherFeedback'],
      updatedAt: _parseDate(rawUpdated),
    );
  }
}
