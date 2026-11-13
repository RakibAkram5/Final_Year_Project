/// A student's attempt at an ONLINE quiz, as returned by
/// `/quizzes/:id/attempt` and `/quizzes/:id/submissions`.
///
/// Correctness fields (`isCorrect`, `marksAwarded`, `autoScore`, …) are null
/// until the server reveals them: after the student submits, or always for
/// teachers/admins. The answer key itself is never sent before submission.
class QuizAnswer {
  final String questionId;
  final int? selectedIndex;
  final String answerText;
  final bool? isCorrect;
  final double? marksAwarded;

  const QuizAnswer({
    required this.questionId,
    this.selectedIndex,
    this.answerText = '',
    this.isCorrect,
    this.marksAwarded,
  });

  bool get isAnswered => selectedIndex != null || answerText.trim().isNotEmpty;

  QuizAnswer copyWith({
    int? selectedIndex,
    bool clearSelectedIndex = false,
    String? answerText,
  }) {
    return QuizAnswer(
      questionId: questionId,
      selectedIndex:
          clearSelectedIndex ? null : (selectedIndex ?? this.selectedIndex),
      answerText: answerText ?? this.answerText,
      isCorrect: isCorrect,
      marksAwarded: marksAwarded,
    );
  }

  Map<String, dynamic> toPayload() => {
        'questionId': questionId,
        'selectedIndex': selectedIndex,
        'answerText': answerText,
      };

  factory QuizAnswer.fromMap(Map<String, dynamic> map) {
    return QuizAnswer(
      questionId: (map['question_id'] ?? map['questionId'] ?? '').toString(),
      selectedIndex:
          (map['selected_index'] ?? map['selectedIndex'] as num?)?.toInt(),
      answerText: (map['answer_text'] ?? map['answerText'] ?? '').toString(),
      isCorrect: map['is_correct'] as bool?,
      marksAwarded: (map['marks_awarded'] as num?)?.toDouble(),
    );
  }
}

enum SubmissionStatus { inProgress, submitted, graded }

class QuizSubmission {
  final String id;
  final String quizId;
  final String studentId;
  final String? studentName;
  final SubmissionStatus status;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final DateTime? gradedAt;

  /// When the attempt must be submitted (duration/availability), if any.
  final DateTime? deadline;
  final double? autoScore;
  final double? autoMaxScore;
  final double? finalScore;
  final bool needsReview;
  final String teacherNote;
  final List<QuizAnswer> answers;

  /// Only present once the key may be revealed: questionId -> correct index.
  final Map<String, int> correctIndexes;

  const QuizSubmission({
    required this.id,
    required this.quizId,
    required this.studentId,
    this.studentName,
    required this.status,
    this.startedAt,
    this.submittedAt,
    this.gradedAt,
    this.deadline,
    this.autoScore,
    this.autoMaxScore,
    this.finalScore,
    this.needsReview = false,
    this.teacherNote = '',
    this.answers = const [],
    this.correctIndexes = const {},
  });

  bool get isInProgress => status == SubmissionStatus.inProgress;
  bool get isClosed => !isInProgress;

  QuizAnswer? answerFor(String questionId) {
    for (final a in answers) {
      if (a.questionId == questionId) return a;
    }
    return null;
  }

  static SubmissionStatus _status(dynamic raw) {
    switch ((raw ?? '').toString().toUpperCase()) {
      case 'GRADED':
        return SubmissionStatus.graded;
      case 'SUBMITTED':
        return SubmissionStatus.submitted;
      default:
        return SubmissionStatus.inProgress;
    }
  }

  static DateTime? _date(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  factory QuizSubmission.fromMap(Map<String, dynamic> map) {
    final rawKey = map['correct_indexes'];
    final key = <String, int>{};
    if (rawKey is Map) {
      rawKey.forEach((k, v) {
        if (v is num) key[k.toString()] = v.toInt();
      });
    }
    return QuizSubmission(
      id: (map['id'] ?? '').toString(),
      quizId: (map['quiz_id'] ?? map['quizId'] ?? '').toString(),
      studentId: (map['student_id'] ?? map['studentId'] ?? '').toString(),
      studentName: map['student_name']?.toString(),
      status: _status(map['status']),
      startedAt: _date(map['started_at']),
      submittedAt: _date(map['submitted_at']),
      gradedAt: _date(map['graded_at']),
      deadline: _date(map['deadline']),
      autoScore: (map['auto_score'] as num?)?.toDouble(),
      autoMaxScore: (map['auto_max_score'] as num?)?.toDouble(),
      finalScore: (map['final_score'] as num?)?.toDouble(),
      needsReview: map['needs_review'] == true,
      teacherNote: (map['teacher_note'] ?? '').toString(),
      answers: (map['answers'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => QuizAnswer.fromMap(Map<String, dynamic>.from(a)))
          .toList(),
      correctIndexes: key,
    );
  }
}
