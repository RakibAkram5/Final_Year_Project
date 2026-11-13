import 'dart:convert';

enum QuestionType { mcq, short, long }

/// Which printed block a [PaperSection] represents. Mirrors [QuestionType]
/// but kept separate so the paper layout can evolve independently of the
/// question model (e.g. two short-question groups backed by the same type).
enum SectionKind { mcq, short, long }

class QuizQuestion {
  final String id;
  final String text;
  final QuestionType type;
  final List<String>? options; // For MCQ
  final int? correctIndex; // For MCQ (Teacher reference)
  final double marks;
  final List<String> gradingKeywords; // For 100% Offline AI Checking

  /// Teacher-only model answer / marking guideline shown on the answer key
  /// for short and long questions. Never rendered on the student paper.
  /// Persisted via [QuizModel.paperMeta] (`answers` map) rather than a
  /// dedicated column, so it survives reopen from examination history.
  final String? answerText;

  QuizQuestion({
    required this.id,
    required this.text,
    required this.type,
    this.options,
    this.correctIndex,
    required this.marks,
    this.gradingKeywords = const [],
    this.answerText,
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
      // Harmless extra field for API payloads; the backend ignores unknown
      // keys. Authoritative persistence is via paperMeta.answers.
      'answer_text': answerText,
    };
  }

  QuizQuestion copyWith({
    String? text,
    QuestionType? type,
    List<String>? options,
    int? correctIndex,
    double? marks,
    List<String>? gradingKeywords,
    String? answerText,
  }) {
    return QuizQuestion(
      id: id,
      text: text ?? this.text,
      type: type ?? this.type,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      marks: marks ?? this.marks,
      gradingKeywords: gradingKeywords ?? this.gradingKeywords,
      answerText: answerText ?? this.answerText,
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
      answerText: map['answer_text']?.toString(),
    );
  }
}

/// One printed block of the examination paper (e.g. "Section A – MCQs",
/// "Q2. Write short answers to any 4 parts", "Part II – Long Questions").
///
/// Sections reference questions by id rather than embedding them, so the
/// flat [QuizModel.questions] list stays the single source of truth that
/// grading, take-quiz and reports already consume unchanged.
class PaperSection {
  final String id;
  final SectionKind kind;

  /// Printed heading label, e.g. "Section A", "2", "Part II".
  final String heading;

  /// Instruction line, e.g. "Attempt the following MCQs",
  /// "Write short answers to any 4 parts".
  final String instruction;

  /// Marks awarded per question/part in this section.
  final double marksPerQuestion;

  /// How many questions/parts the student must attempt. `null` means
  /// "attempt all" (used for the MCQ section).
  final int? attemptCount;

  /// Ids into [QuizModel.questions], in printed order.
  final List<String> questionIds;

  const PaperSection({
    required this.id,
    required this.kind,
    required this.heading,
    required this.instruction,
    required this.marksPerQuestion,
    required this.attemptCount,
    required this.questionIds,
  });

  /// Marks this section contributes to the paper total. When the student may
  /// attempt only some parts, only the attempted count scores (this is what
  /// makes the paper's real total differ from a naive sum of every printed
  /// question — the exact inconsistency the reference PDF got wrong).
  double sectionMarks() {
    final count = attemptCount == null
        ? questionIds.length
        : attemptCount!.clamp(0, questionIds.length);
    return count * marksPerQuestion;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind.name,
        'heading': heading,
        'instruction': instruction,
        'marks_per_question': marksPerQuestion,
        'attempt_count': attemptCount,
        'question_ids': questionIds,
      };

  factory PaperSection.fromMap(Map<String, dynamic> map) => PaperSection(
        id: (map['id'] ?? '').toString(),
        kind: SectionKind.values.firstWhere(
          (k) => k.name == map['kind'],
          orElse: () => SectionKind.short,
        ),
        heading: (map['heading'] ?? '').toString(),
        instruction: (map['instruction'] ?? '').toString(),
        marksPerQuestion: (map['marks_per_question'] ?? 0).toDouble(),
        attemptCount: map['attempt_count'] == null
            ? null
            : (map['attempt_count'] as num).toInt(),
        questionIds: (map['question_ids'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
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

  // --- Examination-paper fields (additive; legacy quizzes default these) ---

  /// e.g. "Monthly Test", "Weekly Test", "Midterm", "Final Term",
  /// "Practice Test". Falls back to [session] when empty.
  final String examType;

  /// Human-readable time allowed, e.g. "2 hours", "45 minutes".
  final String timeAllowed;

  /// 'en' or 'ur'. Urdu rendering is gated on a bundled font (see
  /// PdfGeneratorService); the field and code paths exist now so adding the
  /// font later is the only remaining step.
  final String language;

  /// Selected chapters. Falls back to splitting [chapter] when empty.
  final List<String> chapters;

  /// Ordered printed sections. Empty for legacy quizzes, in which case the
  /// PDF generator rebuilds sections from [questions] by type.
  final List<PaperSection> sections;

  // --- Online attempt settings (additive; legacy quizzes are PAPER) ---

  /// 'PAPER' (printed, sat in class) or 'ONLINE' (attempted in the portal).
  final String attemptMode;

  /// Window during which an ONLINE quiz may be started. Null = open-ended.
  final DateTime? availableFrom;
  final DateTime? availableUntil;

  /// Per-attempt time limit for ONLINE quizzes. Null = untimed.
  final int? durationMinutes;

  bool get isOnline => attemptMode == 'ONLINE';

  /// Whether a student may start an attempt right now (window only; the
  /// server is authoritative and re-checks on every call).
  bool get isOpenNow {
    if (!isOnline) return false;
    final now = DateTime.now();
    if (availableFrom != null && now.isBefore(availableFrom!)) return false;
    if (availableUntil != null && now.isAfter(availableUntil!)) return false;
    return true;
  }

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
    this.examType = '',
    this.timeAllowed = '',
    this.language = 'en',
    this.chapters = const [],
    this.sections = const [],
    this.attemptMode = 'PAPER',
    this.availableFrom,
    this.availableUntil,
    this.durationMinutes,
  });

  /// Exam title with a sensible fallback chain.
  String get effectiveExamType =>
      examType.isNotEmpty ? examType : (session.isNotEmpty ? session : 'Test');

  /// Chapters with a fallback that splits the legacy single `chapter` string.
  List<String> get effectiveChapters {
    if (chapters.isNotEmpty) return chapters;
    if (chapter.trim().isEmpty) return const [];
    return chapter
        .split(RegExp(r'[,;]'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
  }

  /// The paper's *actual* total marks, computed from the sections and their
  /// attempt counts. This is the authoritative figure the PDF prints and the
  /// generator validates against the configured target — never a stored
  /// number that can silently drift (the reference PDF's 20-vs-42 bug).
  double get computedTotalMarks {
    if (sections.isEmpty) {
      return questions.fold<double>(0, (sum, q) => sum + q.marks);
    }
    return sections.fold<double>(0, (sum, s) => sum + s.sectionMarks());
  }

  QuizQuestion? questionById(String id) {
    for (final q in questions) {
      if (q.id == id) return q;
    }
    return null;
  }

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
      'paper_meta': paperMeta,
    };
  }

  /// Compact JSON document carrying everything the exam-paper layout and the
  /// teacher answer key need but that the base quiz columns can't store:
  /// section structure, attempt-any counts, exam metadata and short/long
  /// model answers. Persisted into the Quiz.paperMeta JSON column.
  Map<String, dynamic> get paperMeta {
    final answers = <String, String>{};
    for (final q in questions) {
      if (q.answerText != null && q.answerText!.trim().isNotEmpty) {
        answers[q.id] = q.answerText!;
      }
    }
    return {
      'version': 1,
      'exam_type': examType,
      'time_allowed': timeAllowed,
      'language': language,
      'chapters': effectiveChapters,
      'sections': sections.map((s) => s.toMap()).toList(),
      'answers': answers,
    };
  }

  String get paperMetaJson => jsonEncode(paperMeta);

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

  static Map<String, dynamic>? _parsePaperMeta(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Corrupt metadata must never break loading the quiz itself.
      }
    }
    return null;
  }

  factory QuizModel.fromMap(String id, Map<String, dynamic> map) {
    final rawTestDate = map['test_date'] ?? map['testDate'];
    final rawCreatedAt = map['created_at'] ?? map['createdAt'];

    final meta = _parsePaperMeta(map['paper_meta'] ?? map['paperMeta']);

    // Backfill teacher model answers onto the flat question list from
    // paperMeta so the answer key survives a reopen from history.
    final answerMap = <String, String>{};
    if (meta != null && meta['answers'] is Map) {
      (meta['answers'] as Map).forEach((k, v) {
        answerMap[k.toString()] = v.toString();
      });
    }

    final questions = (map['questions'] as List? ?? []).map((q) {
      final parsed = QuizQuestion.fromMap(Map<String, dynamic>.from(q as Map));
      final backfilled = answerMap[parsed.id];
      if (backfilled != null && (parsed.answerText == null)) {
        return parsed.copyWith(answerText: backfilled);
      }
      return parsed;
    }).toList();

    final sections = <PaperSection>[];
    if (meta != null && meta['sections'] is List) {
      for (final s in (meta['sections'] as List)) {
        if (s is Map) {
          sections.add(PaperSection.fromMap(Map<String, dynamic>.from(s)));
        }
      }
    }

    final chapters = <String>[];
    if (meta != null && meta['chapters'] is List) {
      chapters.addAll((meta['chapters'] as List).map((e) => e.toString()));
    }

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
      questions: questions,
      examType: (meta?['exam_type'] ?? '').toString(),
      timeAllowed: (meta?['time_allowed'] ?? '').toString(),
      language: (meta?['language'] ?? 'en').toString(),
      chapters: chapters,
      sections: sections,
      attemptMode:
          (map['attempt_mode'] ?? map['attemptMode'] ?? 'PAPER').toString(),
      availableFrom:
          _parseOptionalDate(map['available_from'] ?? map['availableFrom']),
      availableUntil:
          _parseOptionalDate(map['available_until'] ?? map['availableUntil']),
      durationMinutes:
          ((map['duration_minutes'] ?? map['durationMinutes']) as num?)
              ?.toInt(),
    );
  }

  static DateTime? _parseOptionalDate(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val.toLocal();
    if (val is String && val.trim().isNotEmpty) {
      return DateTime.tryParse(val)?.toLocal();
    }
    return null;
  }

  QuizModel copyWith({
    String? title,
    List<QuizQuestion>? questions,
    List<PaperSection>? sections,
    double? totalMarks,
    String? examType,
    String? timeAllowed,
    String? language,
    List<String>? chapters,
    String? instructions,
    String? attemptMode,
    DateTime? availableFrom,
    DateTime? availableUntil,
    int? durationMinutes,
  }) {
    return QuizModel(
      id: id,
      academyId: academyId,
      classId: classId,
      classLabel: classLabel,
      title: title ?? this.title,
      subject: subject,
      month: month,
      session: session,
      chapter: chapter,
      difficulty: difficulty,
      totalMarks: totalMarks ?? this.totalMarks,
      testDate: testDate,
      instructions: instructions ?? this.instructions,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: createdAt,
      questions: questions ?? this.questions,
      examType: examType ?? this.examType,
      timeAllowed: timeAllowed ?? this.timeAllowed,
      language: language ?? this.language,
      chapters: chapters ?? this.chapters,
      sections: sections ?? this.sections,
      attemptMode: attemptMode ?? this.attemptMode,
      availableFrom: availableFrom ?? this.availableFrom,
      availableUntil: availableUntil ?? this.availableUntil,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }
}
