import '../models/quiz_model.dart';
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
}
