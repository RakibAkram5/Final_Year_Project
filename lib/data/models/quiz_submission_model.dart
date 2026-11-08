import '../remote/api_client.dart';

class AnswerModel {
  final String questionId;
  final String answerText;
  final double marksAwarded;
  final bool
      autoGraded; // True if MCQ, False if Short Answer (needs teacher review)

  AnswerModel({
    required this.questionId,
    required this.answerText,
    required this.marksAwarded,
    required this.autoGraded,
  });

  Map<String, dynamic> toMap() {
    return {
      'question_id': questionId,
      'answer_text': answerText,
      'marks_awarded': marksAwarded,
      'auto_graded': autoGraded,
    };
  }

  factory AnswerModel.fromMap(Map<String, dynamic> map) {
    return AnswerModel(
      questionId: map['question_id'] ?? '',
      answerText: map['answer_text'] ?? '',
      marksAwarded: (map['marks_awarded'] ?? 0).toDouble(),
      autoGraded: map['auto_graded'] ?? false,
    );
  }
}

class QuizSubmissionModel {
  final String id; // Deterministic: {quizId}_{studentUid}
  final String quizId;
  final String classId;
  final String studentId;
  final String studentName;
  final List<AnswerModel> answers;
  final double totalAwarded;
  final double percentage;
  final String gradeLetter;
  final String status; // 'submitted' | 'graded'
  final DateTime submittedAt;
  final DateTime? gradedAt;
  final String? teacherFeedback;

  QuizSubmissionModel({
    required this.id,
    required this.quizId,
    required this.classId,
    required this.studentId,
    required this.studentName,
    required this.answers,
    required this.totalAwarded,
    required this.percentage,
    required this.gradeLetter,
    required this.status,
    required this.submittedAt,
    this.gradedAt,
    this.teacherFeedback,
  });

  // Helper method to calculate grade letter based on percentage
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
      'quiz_id': quizId,
      'class_id': classId,
      'student_id': studentId,
      'student_name': studentName,
      'answers': answers.map((a) => a.toMap()).toList(),
      'total_awarded': totalAwarded,
      'percentage': percentage,
      'grade_letter': gradeLetter,
      'status': status,
      'submitted_at': submittedAt.toUtc().toIso8601String(),
      'graded_at': gradedAt?.toUtc().toIso8601String(),
      'teacher_feedback': teacherFeedback,
    };
  }

  factory QuizSubmissionModel.fromMap(String id, Map<String, dynamic> map) {
    return QuizSubmissionModel(
      id: id,
      quizId: map['quiz_id'] ?? '',
      classId: map['class_id'] ?? '',
      studentId: map['student_id'] ?? '',
      studentName: map['student_name'] ?? '',
      answers: (map['answers'] as List? ?? [])
          .map((a) => AnswerModel.fromMap(a as Map<String, dynamic>))
          .toList(),
      totalAwarded: (map['total_awarded'] ?? 0).toDouble(),
      percentage: (map['percentage'] ?? 0).toDouble(),
      gradeLetter: map['grade_letter'] ?? 'F',
      status: map['status'] ?? 'submitted',
      submittedAt: ApiClient.parseDate(map['submitted_at']) ?? DateTime.now(),
      gradedAt: ApiClient.parseDate(map['graded_at']),
      teacherFeedback: map['teacher_feedback'],
    );
  }
}
