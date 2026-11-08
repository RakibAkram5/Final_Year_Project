import '../models/quiz_model.dart';
import '../models/test_mark_model.dart';
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
    });
    DataChanges.notify(DataTopics.quizzes);
    return QuizModel.fromMap(
        (res['id'] ?? '').toString(), Map<String, dynamic>.from(res as Map));
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
