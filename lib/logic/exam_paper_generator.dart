import 'package:uuid/uuid.dart';

import '../data/exam/curriculum_bank.dart';
import '../data/models/quiz_model.dart';
import 'text_rank_summarizer.dart';

/// Configuration for one short-question group, e.g.
/// "Write short answers to any 4 of the following 6 parts (2 × 4 = 8)".
class ShortGroupConfig {
  final int partsCount; // parts printed
  final int attemptCount; // parts the student must attempt
  final double marksPerPart;

  const ShortGroupConfig({
    required this.partsCount,
    required this.attemptCount,
    required this.marksPerPart,
  });

  /// Marks this group contributes (only attempted parts score).
  double get groupMarks => attemptCount.clamp(0, partsCount) * marksPerPart;
}

/// Everything a teacher configures for a generated examination paper.
class ExamConfig {
  final String title;
  final String subject;
  final String classLabel;
  final String examType; // Monthly Test, Final Term, ...
  final String timeAllowed; // "2 hours"
  final String difficulty; // Easy | Medium | Hard | Mixed
  final String language; // 'en' | 'ur'
  final List<String> chapters;

  // Section A — MCQs
  final int mcqCount;
  final double marksPerMcq;

  // Section B/C — short-question groups
  final List<ShortGroupConfig> shortGroups;

  // Part II — long questions
  final int longCount; // printed
  final int longAttempt; // attempt any N
  final double marksPerLong;

  /// Optional source material (OCR / uploaded notes). When present the
  /// generator draws from it first, falling back to the curriculum bank.
  final String? sourceText;

  const ExamConfig({
    required this.title,
    required this.subject,
    required this.classLabel,
    this.examType = 'Monthly Test',
    this.timeAllowed = '',
    this.difficulty = 'Medium',
    this.language = 'en',
    this.chapters = const [],
    this.mcqCount = 10,
    this.marksPerMcq = 1,
    this.shortGroups = const [
      ShortGroupConfig(partsCount: 6, attemptCount: 4, marksPerPart: 2),
    ],
    this.longCount = 3,
    this.longAttempt = 2,
    this.marksPerLong = 8,
    this.sourceText,
  });

  /// Authoritative total marks implied by this configuration (respecting
  /// attempt-any counts). Printed on the paper and used for validation.
  double get computedTotalMarks {
    final mcq = mcqCount * marksPerMcq;
    final short = shortGroups.fold<double>(0, (sum, g) => sum + g.groupMarks);
    final long = longAttempt.clamp(0, longCount) * marksPerLong;
    return mcq + short + long;
  }
}

/// Outcome of a generation attempt. `ok` is true only when a usable paper was
/// produced; warnings explain any shortfall (e.g. "requested 20 MCQs but only
/// 12 vetted questions were available for the selected chapters").
class GenerationResult {
  final QuizModel? quiz;
  final List<String> warnings;
  final String? error;
  final MarksBreakdown? marks;
  final String engine; // 'bank' | 'source' | 'hybrid' | 'remote'

  const GenerationResult({
    this.quiz,
    this.warnings = const [],
    this.error,
    this.marks,
    this.engine = 'bank',
  });

  bool get ok => quiz != null && error == null;
}

/// A validated breakdown of where the paper's marks come from. Surfacing this
/// to the teacher is what prevents the reference PDF's defect (header said 20,
/// sections added to 42).
class MarksBreakdown {
  final double mcqMarks;
  final double shortMarks;
  final double longMarks;
  final double? configuredTarget;

  const MarksBreakdown({
    required this.mcqMarks,
    required this.shortMarks,
    required this.longMarks,
    this.configuredTarget,
  });

  double get total => mcqMarks + shortMarks + longMarks;

  /// True when a teacher-entered target disagrees with the real total.
  bool get mismatch =>
      configuredTarget != null && (configuredTarget! - total).abs() > 0.01;
}

/// Offline, deterministic-ish examination paper generator.
///
/// Strategy (hybrid):
///   1. If [ExamConfig.sourceText] is supplied, mine it with TextRank for
///      short/long questions and simple definition MCQs.
///   2. Top up each question type from the vetted [CurriculumBank] for the
///      subject, filtered by the selected chapters and difficulty.
///   3. If neither source nor bank can supply a type, the paper is still
///      produced for the types that worked, and a warning names the shortfall
///      — the generator never fabricates subject-specific facts.
///
/// A remote LLM path (when the backend has a key configured) is handled by the
/// caller; this class is the always-available fallback.
class ExamPaperGenerator {
  final Uuid _uuid = const Uuid();

  GenerationResult generate(
    ExamConfig config, {
    required String academyId,
    required String classId,
    required String createdByUid,
    required String createdByName,
    List<BankItem> remoteItems = const [],
  }) {
    final warnings = <String>[];

    // Pools of available questions per type, de-duplicated by normalised text.
    final used = <String>{};
    final mcqPool = <QuizQuestion>[];
    final shortPool = <QuizQuestion>[];
    final longPool = <QuizQuestion>[];

    String norm(String t) =>
        t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    bool take(String text) => used.add(norm(text));

    // --- 0. Remote (LLM) items, if the caller fetched any (preferred) ---
    final usingRemote = remoteItems.isNotEmpty;
    for (final item in remoteItems) {
      if (!take(item.text)) continue;
      final q = _fromBank(item);
      switch (item.type) {
        case QuestionType.mcq:
          mcqPool.add(q);
        case QuestionType.short:
          shortPool.add(q);
        case QuestionType.long:
          longPool.add(q);
      }
    }

    // --- 1. Source material (if provided) ---
    final source = config.sourceText?.trim() ?? '';
    final usingSource = source.length > 40;
    if (usingSource) {
      _fromSource(source, config, take, mcqPool, shortPool, longPool);
    }

    // --- 2. Curriculum bank top-up ---
    final bank = CurriculumBank.forSubject(config.subject);
    if (bank != null) {
      final filtered = _filterBank(bank, config);
      for (final item in filtered) {
        if (!take(item.text)) continue;
        final q = _fromBank(item);
        switch (item.type) {
          case QuestionType.mcq:
            mcqPool.add(q);
          case QuestionType.short:
            shortPool.add(q);
          case QuestionType.long:
            longPool.add(q);
        }
      }
    }

    // Nothing to work with at all.
    if (mcqPool.isEmpty && shortPool.isEmpty && longPool.isEmpty) {
      return GenerationResult(
        error: bank == null && !usingSource && !usingRemote
            ? 'No vetted question bank exists for "${config.subject}". Scan or '
                'upload the course material first, or configure an AI key, so '
                'the paper is built from real content instead of guesses.'
            : 'Not enough source material to generate questions. Add more '
                'notes or select different chapters.',
      );
    }

    // --- 3. Assemble sections to the requested shape ---
    final questions = <QuizQuestion>[];
    final sections = <PaperSection>[];

    // Section A — MCQs
    double mcqMarks = 0;
    if (config.mcqCount > 0) {
      final picked = _pick(mcqPool, config.mcqCount, config.marksPerMcq);
      if (picked.length < config.mcqCount) {
        warnings.add(
            'Requested ${config.mcqCount} MCQs but only ${picked.length} were '
            'available for the selected chapters.');
      }
      if (picked.isNotEmpty) {
        questions.addAll(picked);
        mcqMarks = picked.length * config.marksPerMcq;
        sections.add(PaperSection(
          id: _uuid.v4(),
          kind: SectionKind.mcq,
          heading: 'Section A',
          instruction:
              'Attempt all of the following multiple choice questions.',
          marksPerQuestion: config.marksPerMcq,
          attemptCount: null, // attempt all
          questionIds: picked.map((q) => q.id).toList(),
        ));
      }
    }

    // Short-question groups
    double shortMarks = 0;
    for (var gi = 0; gi < config.shortGroups.length; gi++) {
      final g = config.shortGroups[gi];
      final picked = _pick(shortPool, g.partsCount, g.marksPerPart);
      if (picked.isEmpty) {
        warnings.add(
            'Short-question group ${gi + 1} could not be filled — no short '
            'questions left for the selected chapters.');
        continue;
      }
      if (picked.length < g.partsCount) {
        warnings.add(
            'Short group ${gi + 1}: requested ${g.partsCount} parts but only '
            '${picked.length} were available.');
      }
      final attempt = g.attemptCount.clamp(1, picked.length);
      questions.addAll(picked);
      shortMarks += attempt * g.marksPerPart;
      sections.add(PaperSection(
        id: _uuid.v4(),
        kind: SectionKind.short,
        heading: '', // numbered at render time
        instruction: picked.length <= attempt
            ? 'Write short answers to all of the following parts.'
            : 'Write short answers to any $attempt of the following '
                '${picked.length} parts.',
        marksPerQuestion: g.marksPerPart,
        attemptCount: attempt,
        questionIds: picked.map((q) => q.id).toList(),
      ));
    }

    // Part II — long questions
    double longMarks = 0;
    if (config.longCount > 0) {
      final picked = _pick(longPool, config.longCount, config.marksPerLong);
      if (picked.isEmpty) {
        warnings.add('No long questions were available for the selected '
            'chapters.');
      } else {
        if (picked.length < config.longCount) {
          warnings.add('Requested ${config.longCount} long questions but only '
              '${picked.length} were available.');
        }
        final attempt = config.longAttempt.clamp(1, picked.length);
        questions.addAll(picked);
        longMarks = attempt * config.marksPerLong;
        sections.add(PaperSection(
          id: _uuid.v4(),
          kind: SectionKind.long,
          heading: 'Part II',
          instruction: picked.length <= attempt
              ? 'Attempt all of the following questions.'
              : 'Attempt any $attempt of the following ${picked.length} '
                  'questions.',
          marksPerQuestion: config.marksPerLong,
          attemptCount: attempt,
          questionIds: picked.map((q) => q.id).toList(),
        ));
      }
    }

    if (questions.isEmpty) {
      return const GenerationResult(
          error: 'Could not generate any questions for this configuration.');
    }

    final marks = MarksBreakdown(
      mcqMarks: mcqMarks,
      shortMarks: shortMarks,
      longMarks: longMarks,
    );

    final instructions = _instructionLine(config, sections);

    final quiz = QuizModel(
      id: _uuid.v4(),
      academyId: academyId,
      classId: classId,
      classLabel: config.classLabel,
      title: config.title.trim().isEmpty
          ? '${config.subject} ${config.examType}'
          : config.title.trim(),
      subject: config.subject,
      month: _currentMonth(),
      session: config.examType,
      chapter: config.chapters.join(', '),
      difficulty: config.difficulty,
      totalMarks: marks.total,
      testDate: DateTime.now(),
      instructions: instructions,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: DateTime.now(),
      questions: questions,
      examType: config.examType,
      timeAllowed: config.timeAllowed,
      language: config.language,
      chapters: config.chapters,
      sections: sections,
    );

    return GenerationResult(
      quiz: quiz,
      warnings: warnings,
      marks: marks,
      engine: usingRemote
          ? 'AI'
          : usingSource
              ? (bank != null ? 'hybrid' : 'source')
              : 'bank',
    );
  }

  /// Validates an already-built config against a teacher-entered target total.
  MarksBreakdown validateMarks(ExamConfig config, {double? target}) {
    final mcq = config.mcqCount * config.marksPerMcq;
    final short =
        config.shortGroups.fold<double>(0, (s, g) => s + g.groupMarks);
    final long =
        config.longAttempt.clamp(0, config.longCount) * config.marksPerLong;
    return MarksBreakdown(
      mcqMarks: mcq,
      shortMarks: short,
      longMarks: long,
      configuredTarget: target,
    );
  }

  // --- helpers ---

  List<BankItem> _filterBank(List<BankItem> bank, ExamConfig config) {
    var items = bank.toList();
    if (config.chapters.isNotEmpty) {
      final wanted = config.chapters.map((c) => c.toLowerCase().trim()).toSet();
      final byChapter = items
          .where((i) => wanted.contains(i.chapter.toLowerCase().trim()))
          .toList();
      // Only narrow by chapter when it actually matches something, otherwise
      // fall back to the whole subject so a mistyped chapter never empties it.
      if (byChapter.isNotEmpty) items = byChapter;
    }
    if (config.difficulty != 'Mixed') {
      // Difficulty is a preference, not a hard filter: matching items come
      // first so the paper leans to the requested level, but questions are
      // never dropped (which would starve a section and force a short paper).
      final preferred = <BankItem>[];
      final rest = <BankItem>[];
      for (final item in items) {
        (item.difficulty == config.difficulty ? preferred : rest).add(item);
      }
      items = [...preferred, ...rest];
    }
    return items;
  }

  QuizQuestion _fromBank(BankItem item) => QuizQuestion(
        id: _uuid.v4(),
        text: item.text,
        type: item.type,
        options: item.options,
        correctIndex: item.correctIndex,
        marks: 1, // real marks assigned when picked into a section
        gradingKeywords: item.keywords,
        answerText: item.answer,
      );

  /// Picks up to [count] questions from [pool] (removing them so no question
  /// repeats across sections) and stamps each with [marks].
  List<QuizQuestion> _pick(List<QuizQuestion> pool, int count, double marks) {
    final out = <QuizQuestion>[];
    while (out.length < count && pool.isNotEmpty) {
      final q = pool.removeAt(0);
      out.add(q.copyWith(marks: marks));
    }
    return out;
  }

  void _fromSource(
    String source,
    ExamConfig config,
    bool Function(String) take,
    List<QuizQuestion> mcqPool,
    List<QuizQuestion> shortPool,
    List<QuizQuestion> longPool,
  ) {
    final ranked = TextRankSummarizer.rankSentences(source)
        .map((s) => s.replaceAll(RegExp(r'[.?!]+$'), '').trim())
        .where((s) => s.length > 15)
        .toList();

    // Definition-style MCQs from "X is Y" / "X refers to Y".
    for (final sentence in ranked) {
      if (mcqPool.length >= config.mcqCount) break;
      if (!(sentence.contains(' is ') || sentence.contains(' refers to '))) {
        continue;
      }
      final parts = sentence.split(RegExp(r' is | refers to '));
      if (parts.length != 2 ||
          parts[0].trim().isEmpty ||
          parts[1].trim().isEmpty) {
        continue;
      }
      final text =
          'What ${sentence.contains(' refers to ') ? 'refers to' : 'is'} '
          '${parts[1].trim()}?';
      if (!take(text)) continue;
      mcqPool.add(QuizQuestion(
        id: _uuid.v4(),
        text: text,
        type: QuestionType.mcq,
        options: [
          parts[0].trim(),
          'None of the above',
          'Both A and B',
          'Incorrect definition',
        ],
        correctIndex: 0,
        marks: config.marksPerMcq,
        gradingKeywords: _keywords(sentence),
        answerText: parts[0].trim(),
      ));
    }

    final remaining = ranked.where((s) {
      return !mcqPool.any((q) =>
          q.gradingKeywords.isNotEmpty &&
          s.toLowerCase().contains(q.gradingKeywords.first));
    }).toList();

    // Long questions from the most substantial sentences.
    for (final sentence in remaining) {
      if (longPool.length >= config.longCount) break;
      if (sentence.length < 80) continue;
      final preview =
          sentence.length > 70 ? '${sentence.substring(0, 70)}...' : sentence;
      final text = 'Explain in detail: $preview';
      if (!take(text)) continue;
      longPool.add(QuizQuestion(
        id: _uuid.v4(),
        text: text,
        type: QuestionType.long,
        marks: config.marksPerLong,
        gradingKeywords: _keywords(sentence),
        answerText:
            'Expected points from the source material: $sentence. Award marks '
            'for coverage of these key ideas and correct explanation.',
      ));
    }

    // Short questions from the next-most-important sentences.
    final shortNeeded =
        config.shortGroups.fold<int>(0, (s, g) => s + g.partsCount);
    for (final sentence in remaining) {
      if (shortPool.length >= shortNeeded) break;
      if (sentence.contains('?')) continue;
      final text = 'Briefly explain: $sentence';
      if (!take(text)) continue;
      shortPool.add(QuizQuestion(
        id: _uuid.v4(),
        text: text,
        type: QuestionType.short,
        marks: 2,
        gradingKeywords: _keywords(sentence),
        answerText:
            'Key points: $sentence. Award marks for mentioning these ideas.',
      ));
    }
  }

  static const _stop = {
    'the',
    'a',
    'an',
    'and',
    'or',
    'but',
    'is',
    'are',
    'was',
    'were',
    'be',
    'to',
    'of',
    'in',
    'on',
    'at',
    'by',
    'for',
    'with',
    'as',
    'this',
    'that',
    'it',
    'its',
    'they',
    'which',
    'from',
    'can',
    'may',
    'not',
    'has',
    'have',
  };

  List<String> _keywords(String sentence, {int max = 6}) {
    final words = sentence
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 3 && !_stop.contains(w))
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return words.take(max).toList();
  }

  String _instructionLine(ExamConfig config, List<PaperSection> sections) {
    final buf = <String>[];
    if (config.mcqCount > 0) {
      buf.add('attempt all MCQs in Section A');
    }
    final shortAttempt =
        config.shortGroups.fold<int>(0, (s, g) => s + g.attemptCount);
    if (shortAttempt > 0) {
      buf.add('answer the required short questions');
    }
    if (config.longCount > 0) {
      buf.add('attempt the required long questions in Part II');
    }
    if (buf.isEmpty) return 'Answer all questions.';
    final body = buf.join('; ');
    return 'Read each question carefully. Please $body. '
        'Write your answers neatly.';
  }

  String _currentMonth() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[DateTime.now().month - 1];
  }
}
