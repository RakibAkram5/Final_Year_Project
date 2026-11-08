import 'package:flutter/material.dart';
import '../data/models/quiz_model.dart';
import '../data/models/test_mark_model.dart';
import '../data/remote/quiz_service.dart';

class QuizProvider extends ChangeNotifier {
  final QuizService _service = QuizService();

  bool _loading = false;
  bool get loading => _loading;

  void _setLoading(bool val) {
    _loading = val;
    notifyListeners();
  }

  // --- Actions ---

  Future<void> createQuiz(QuizModel quiz) async {
    _setLoading(true);
    try {
      await _service.createQuiz(quiz);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteQuiz(String quizId, String academyId) async {
    _setLoading(true);
    try {
      await _service.deleteQuiz(quizId, academyId);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateQuestions(
      String quizId, List<QuizQuestion> questions) async {
    await _service.updateQuestions(quizId, questions);
  }

  Future<void> uploadBulkMarks(List<TestMarkModel> marksList) async {
    _setLoading(true);
    try {
      await _service.uploadBulkMarks(marksList);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteMark(String markId, {String academyId = ''}) async {
    await _service.deleteMark(markId, academyId);
  }

  // --- Streams (Real-time data) ---

  /// Watch all tests created for a specific class in an academy
  Stream<List<QuizModel>> watchTeacherQuizzes(
      String classId, String academyId) {
    return _service.watchQuizzesByClass(classId, academyId);
  }

  /// Watch tests across several classes at once (e.g. a student's full
  /// subject list) — used to surface upcoming tests on the dashboard.
  Stream<List<QuizModel>> watchQuizzesForClasses(
      List<String> classIds, String academyId) {
    return _service.watchQuizzesForClasses(classIds, academyId);
  }

  /// Watch marks for a specific test (for Teacher/Admin review)
  Stream<List<TestMarkModel>> watchQuizResults(
      String quizId, String academyId) {
    return _service.watchMarksByQuiz(quizId, academyId);
  }

  /// Watch all test results for a specific student (for Report Card)
  Stream<List<TestMarkModel>> watchStudentResults(
      String uid, String academyId) {
    return _service.watchStudentMarks(uid, academyId);
  }

  /// Watch all marks for a class (for Admin Analytics)
  Stream<List<TestMarkModel>> watchClassResults(
      String classId, String academyId) {
    return _service.watchClassMarks(classId, academyId);
  }

  /// NEW: Compiles monthly report data for a class
  Stream<Map<String, dynamic>> watchMonthlyClassReport(
      String classId, String month, String academyId) {
    return watchClassResults(classId, academyId).asyncMap((marks) async {
      // 1. Get all quizzes for this class and month to know total possible marks
      final quizzes =
          await _service.watchQuizzesByClass(classId, academyId).first;
      final monthlyQuizzes = quizzes.where((q) => q.month == month).toList();

      if (monthlyQuizzes.isEmpty) {
        return {
          'quizCount': 0,
          'subjects': [],
          'studentStats': <String, Map<String, dynamic>>{},
        };
      }

      final Map<String, Map<String, dynamic>> studentStats = {};

      for (var q in monthlyQuizzes) {
        final qMarks = marks.where((m) => m.quizId == q.id).toList();
        for (var m in qMarks) {
          if (!studentStats.containsKey(m.studentId)) {
            studentStats[m.studentId] = {
              'name': m.studentName,
              'obtained': 0.0,
              'total': 0.0,
              'subjects': <String, Map<String, double>>{},
            };
          }

          final stats = studentStats[m.studentId]!;
          stats['obtained'] = (stats['obtained'] as double) + m.marksObtained;
          stats['total'] = (stats['total'] as double) + m.totalMarks;

          final subjects =
              stats['subjects'] as Map<String, Map<String, double>>;
          if (!subjects.containsKey(q.subject)) {
            subjects[q.subject] = {'obtained': 0.0, 'total': 0.0};
          }
          subjects[q.subject]!['obtained'] =
              subjects[q.subject]!['obtained']! + m.marksObtained;
          subjects[q.subject]!['total'] =
              subjects[q.subject]!['total']! + m.totalMarks;
        }
      }

      return {
        'quizCount': monthlyQuizzes.length,
        'subjects': monthlyQuizzes.map((q) => q.subject).toSet().toList(),
        'studentStats': studentStats,
      };
    });
  }
}
