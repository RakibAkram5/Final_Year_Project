import '../models/quiz_model.dart';
import '../models/quiz_submission_model.dart';
import '../models/test_mark_model.dart';
import '../exam/curriculum_bank.dart';
import 'api_client.dart';
import 'live_query.dart';

/// Quizzes and test marks over REST (`/quizzes`, `/quizzes/marks`).
///
/// Streams re-fetch after any local quiz/mark change and deliver failures
/// as stream errors rather than empty lists.
class QuizService {
  final ApiClient _api = ApiClient();

  List<QuizModel> _quizzes(dynamic res) => (res as List)
      .map((item) => QuizModel.fromMap(
          (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
      .toList();

  List<TestMarkModel> _marks(dynamic res) => (res as List)
      .map((item) => TestMarkModel.fromMap(
          (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
      .toList();

  Future<QuizModel> createQuiz(QuizModel quiz) async {
    final res = await _api.post('/quizzes', {
      'classId': quiz.classId,
      'classLabel': quiz.classLabel,
      'title': quiz.title,
      'subject': quiz.subject,
      'month': quiz.month,
      'session': quiz.session,
      'chapter': quiz.chapter,
      'difficulty': quiz.difficulty,
      'testDate': quiz.testDate.toUtc().toIso8601String(),
      'totalMarks': quiz.totalMarks.round(),
      'instructions': quiz.instructions,
      'questions': quiz.questions.map((q) => q.toMap()).toList(),
      // Exam-paper layout + teacher answer key. Backend persists it into the
      // Quiz.paperMeta JSON column when present; older backends ignore it and
      // the paper still saves (layout then falls back to type-grouping on
      // reopen).
      'paperMeta': quiz.paperMeta,
      // Online attempt settings (ignored by backends that predate them).
      'attemptMode': quiz.attemptMode,
      'availableFrom': quiz.availableFrom?.toUtc().toIso8601String(),
      'availableUntil': quiz.availableUntil?.toUtc().toIso8601String(),
      'durationMinutes': quiz.durationMinutes,
    });
    DataChanges.notify(DataTopics.quizzes);
    return QuizModel.fromMap(
        (res['id'] ?? '').toString(), Map<String, dynamic>.from(res as Map));
  }

  /// Optional AI question generation. Returns curriculum items when the server
  /// has an AI key configured, or `null` (not configured / upstream failure)
  /// so the caller transparently falls back to the offline generator.
  Future<List<BankItem>?> aiGenerateItems({
    required String subject,
    required String classLabel,
    required List<String> chapters,
    required String difficulty,
    required int mcqCount,
    required int shortCount,
    required int longCount,
  }) async {
    try {
      final res = await _api.post('/quizzes/ai-generate', {
        'subject': subject,
        'classLabel': classLabel,
        'chapters': chapters,
        'difficulty': difficulty,
        'mcqCount': mcqCount,
        'shortCount': shortCount,
        'longCount': longCount,
      });
      final items = (res is Map ? res['items'] : null) as List?;
      if (items == null) return null;
      return items
          .whereType<Map>()
          .map((m) => _bankItemFromJson(Map<String, dynamic>.from(m)))
          .whereType<BankItem>()
          .toList();
    } on ApiException {
      // 501 (not configured) or an upstream error — caller uses offline.
      return null;
    } catch (_) {
      return null;
    }
  }

  BankItem? _bankItemFromJson(Map<String, dynamic> m) {
    final typeStr = (m['type'] ?? '').toString();
    final type = QuestionType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => QuestionType.short,
    );
    final text = (m['text'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    final options = (m['options'] as List?)?.map((e) => e.toString()).toList();
    if (type == QuestionType.mcq && (options == null || options.length < 4)) {
      return null;
    }
    return BankItem(
      type: type,
      chapter: (m['chapter'] ?? '').toString(),
      text: text,
      options: type == QuestionType.mcq ? options : null,
      correctIndex: type == QuestionType.mcq
          ? ((m['correctIndex'] as num?)?.toInt() ?? 0).clamp(0, 3)
          : null,
      answer: (m['answer'] ?? '').toString(),
      keywords: (m['keywords'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      difficulty: ['Easy', 'Medium', 'Hard'].contains(m['difficulty'])
          ? m['difficulty'].toString()
          : 'Medium',
    );
  }

  Future<void> updateQuestions(
      String quizId, List<QuizQuestion> questions) async {
    await _api.put('/quizzes/$quizId/questions', {
      'questions': questions.map((q) => q.toMap()).toList(),
    });
    DataChanges.notify(DataTopics.quizzes);
  }

  Future<QuizModel> getQuiz(String quizId) async => QuizModel.fromMap(quizId,
      Map<String, dynamic>.from(await _api.get('/quizzes/$quizId') as Map));

  Stream<List<QuizModel>> watchQuizzesByClass(
          String classId, String academyId) =>
      liveQuery(
          DataTopics.quizzes,
          () async => _quizzes(await _api
              .get('/quizzes?classId=${Uri.encodeComponent(classId)}')));

  Stream<List<QuizModel>> watchQuizzesForClasses(
      List<String> classIds, String academyId) {
    final wanted = classIds.toSet();
    return liveQuery(DataTopics.quizzes, () async {
      // The server already limits the list to classes the caller may see.
      final all = _quizzes(await _api.get('/quizzes'));
      return all.where((q) => wanted.contains(q.classId)).toList();
    });
  }

  Future<void> deleteQuiz(String quizId, String academyId) async {
    await _api.delete('/quizzes/$quizId');
    DataChanges.notify(DataTopics.quizzes);
    DataChanges.notify(DataTopics.marks);
  }

  Future<void> saveTestMark(TestMarkModel mark) async {
    await _api.post('/quizzes/marks', {
      'quizId': mark.quizId,
      'studentId': mark.studentId,
      'marksObtained': mark.marksObtained,
      'teacherFeedback': mark.teacherFeedback,
    });
    DataChanges.notify(DataTopics.marks);
  }

  Stream<List<TestMarkModel>> watchStudentMarks(
          String studentId, String academyId) =>
      liveQuery(
          DataTopics.marks,
          () async =>
              _marks(await _api.get('/quizzes/marks/student/$studentId')));

  Future<List<TestMarkModel>> getAllAcademyMarks(String academyId,
      {String? month}) async {
    final path = month == null || month.isEmpty
        ? '/quizzes/marks/academy'
        : '/quizzes/marks/academy?month=${Uri.encodeComponent(month)}';
    return _marks(await _api.get(path));
  }

  /// Saves every mark; stops at the first failure and reports how many
  /// were saved so the caller never shows a false "all saved".
  Future<void> uploadBulkMarks(List<TestMarkModel> marks) async {
    var saved = 0;
    try {
      for (final m in marks) {
        await _api.post('/quizzes/marks', {
          'quizId': m.quizId,
          'studentId': m.studentId,
          'marksObtained': m.marksObtained,
          'teacherFeedback': m.teacherFeedback,
        });
        saved++;
      }
    } catch (e) {
      throw ApiException(
          'Saved $saved of ${marks.length} marks before an error: $e');
    } finally {
      if (saved > 0) DataChanges.notify(DataTopics.marks);
    }
  }

  Future<void> deleteMark(String markId, String academyId) async {
    await _api.delete('/quizzes/marks/$markId');
    DataChanges.notify(DataTopics.marks);
  }

  Stream<List<TestMarkModel>> watchMarksByQuiz(
          String quizId, String academyId) =>
      liveQuery(DataTopics.marks,
          () async => _marks(await _api.get('/quizzes/marks/quiz/$quizId')));

  Stream<List<TestMarkModel>> watchClassMarks(
          String classId, String academyId) =>
      liveQuery(DataTopics.marks,
          () async => _marks(await _api.get('/quizzes/marks/class/$classId')));

  // --- Online attempts -----------------------------------------------------

  QuizSubmission _submission(dynamic res) =>
      QuizSubmission.fromMap(Map<String, dynamic>.from(res as Map));

  /// Starts (or resumes) the signed-in student's attempt.
  Future<QuizSubmission> startAttempt(String quizId) async =>
      _submission(await _api.post('/quizzes/$quizId/attempt', {}));

  /// Autosaves answers while the attempt is in progress.
  Future<QuizSubmission> saveAnswers(
      String quizId, List<QuizAnswer> answers) async {
    return _submission(await _api.put('/quizzes/$quizId/attempt/answers', {
      'answers': answers.map((a) => a.toPayload()).toList(),
    }));
  }

  /// Finalises the attempt. Safe to retry: a second call returns the
  /// already-graded submission unchanged.
  Future<QuizSubmission> submitAttempt(
      String quizId, List<QuizAnswer> answers) async {
    final res = await _api.post('/quizzes/$quizId/attempt/submit', {
      'answers': answers.map((a) => a.toPayload()).toList(),
    });
    DataChanges.notify(DataTopics.quizSubmissions);
    DataChanges.notify(DataTopics.marks);
    return _submission(res);
  }

  /// The attempt for [studentId] (own attempt when null). Returns null when
  /// the student has not started this quiz.
  Future<QuizSubmission?> getAttempt(String quizId, {String? studentId}) async {
    try {
      final suffix = studentId == null
          ? ''
          : '?studentId=${Uri.encodeQueryComponent(studentId)}';
      return _submission(await _api.get('/quizzes/$quizId/attempt$suffix'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Teacher/admin: every submission for a quiz, refreshed on changes.
  Stream<List<QuizSubmission>> watchSubmissions(String quizId) => liveQuery(
      DataTopics.quizSubmissions,
      () async => ((await _api.get('/quizzes/$quizId/submissions')) as List)
          .map((e) => _submission(e))
          .toList());

  /// Teacher/admin: award marks for written answers (and an optional note).
  Future<QuizSubmission> gradeSubmission(
    String quizId,
    String submissionId, {
    required Map<String, double> marksByQuestion,
    String? teacherNote,
  }) async {
    final res =
        await _api.put('/quizzes/$quizId/submissions/$submissionId/grade', {
      'marks': marksByQuestion.entries
          .map((e) => {'questionId': e.key, 'marksAwarded': e.value})
          .toList(),
      if (teacherNote != null) 'teacherNote': teacherNote,
    });
    DataChanges.notify(DataTopics.quizSubmissions);
    DataChanges.notify(DataTopics.marks);
    return _submission(res);
  }
}
