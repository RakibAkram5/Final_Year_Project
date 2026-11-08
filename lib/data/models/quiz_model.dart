enum QuestionType { mcq, short, long }

class QuizQuestion {
  final String id;
  final String text;
  final QuestionType type;
  final List<String>? options; // For MCQ
  final int? correctIndex; // For MCQ (Teacher reference)
  final double marks;
  final List<String> gradingKeywords; // NEW: For 100% Offline AI Checking

  QuizQuestion({
    required this.id,
    required this.text,
    required this.type,
    this.options,
    this.correctIndex,
    required this.marks,
    this.gradingKeywords = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'type': type.name,
      'options': options,
      'correct_index': correctIndex,
      'marks': marks,
      'grading_keywords': gradingKeywords,
    };
  }

  QuizQuestion copyWith({
    String? text,
    QuestionType? type,
    List<String>? options,
    int? correctIndex,
    double? marks,
    List<String>? gradingKeywords,
  }) {
    return QuizQuestion(
      id: id,
      text: text ?? this.text,
      type: type ?? this.type,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      marks: marks ?? this.marks,
      gradingKeywords: gradingKeywords ?? this.gradingKeywords,
    );
  }

  factory QuizQuestion.fromMap(Map<String, dynamic> map) {
    return QuizQuestion(
      id: map['id'] ?? '',
      text: map['text'] ?? '',
      type: QuestionType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => QuestionType.short,
      ),
      options:
          map['options'] != null ? List<String>.from(map['options']) : null,
      correctIndex: map['correct_index'],
      marks: (map['marks'] ?? 0).toDouble(),
      gradingKeywords: (map['grading_keywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class QuizModel {
  final String id;
  final String academyId;
  final String classId;
  final String classLabel;
  final String title;
  final String subject;
  final String month;
  final String session;
  final String chapter;
  final String difficulty;
  final double totalMarks;
  final DateTime testDate;
  final String instructions;
  final String createdByUid;
  final String createdByName;
  final DateTime? createdAt;
  final List<QuizQuestion> questions;

  QuizModel({
    required this.id,
    required this.academyId,
    required this.classId,
    required this.classLabel,
    required this.title,
    required this.subject,
    required this.month,
    required this.session,
    required this.chapter,
    required this.difficulty,
    required this.totalMarks,
    required this.testDate,
    required this.instructions,
    required this.createdByUid,
    required this.createdByName,
    this.createdAt,
    required this.questions,
  });

  Map<String, dynamic> toMap() {
    return {
      'academy_id': academyId,
      'class_id': classId,
      'class_label': classLabel,
      'title': title,
      'subject': subject,
      'month': month,
      'session': session,
      'chapter': chapter,
      'difficulty': difficulty,
      'total_marks': totalMarks,
      'test_date': testDate.toUtc().toIso8601String(),
      'instructions': instructions,
      'created_by_uid': createdByUid,
      'created_by_name': createdByName,
      'created_at': createdAt != null
          ? createdAt!.toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String(),
      'questions': questions.map((q) => q.toMap()).toList(),
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

  factory QuizModel.fromMap(String id, Map<String, dynamic> map) {
    final rawTestDate = map['test_date'] ?? map['testDate'];
    final rawCreatedAt = map['created_at'] ?? map['createdAt'];

    return QuizModel(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: map['academy_id'] ?? map['academyId'] ?? '',
      classId: map['class_id'] ?? map['classId'] ?? '',
      classLabel: map['class_label'] ?? map['classLabel'] ?? '',
      title: map['title'] ?? '',
      subject: map['subject'] ?? '',
      month: map['month'] ?? '',
      session: map['session'] ?? '',
      chapter: map['chapter'] ?? '',
      difficulty: map['difficulty'] ?? 'Medium',
      totalMarks: ((map['total_marks'] ?? map['totalMarks']) ?? 0).toDouble(),
      testDate: _parseDate(rawTestDate),
      instructions: map['instructions'] ?? '',
      createdByUid: map['created_by_uid'] ?? map['createdById'] ?? '',
      createdByName: map['created_by_name'] ?? map['createdByName'] ?? '',
      createdAt: rawCreatedAt != null ? _parseDate(rawCreatedAt) : null,
      questions: (map['questions'] as List? ?? [])
          .map((q) => QuizQuestion.fromMap(q as Map<String, dynamic>))
          .toList(),
    );
  }
}
