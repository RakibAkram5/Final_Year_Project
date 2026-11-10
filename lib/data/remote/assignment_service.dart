import 'api_client.dart';
import 'live_query.dart';

class AssignmentSubmission {
  final String id;
  final String studentId;
  final String studentName;
  final String? note;
  final DateTime submittedAt;
  final double? marks;
  final String? feedback;
  final DateTime? gradedAt;
  final int fileCount;
  final bool late;

  const AssignmentSubmission({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.submittedAt,
    this.note,
    this.marks,
    this.feedback,
    this.gradedAt,
    this.fileCount = 0,
    this.late = false,
  });

  factory AssignmentSubmission.fromJson(Map<String, dynamic> j) =>
      AssignmentSubmission(
        id: j['id'].toString(),
        studentId: (j['studentId'] ?? '').toString(),
        studentName: (j['studentName'] ?? 'Student').toString(),
        note: j['note']?.toString(),
        submittedAt: ApiClient.parseDateOr(j['submittedAt'], DateTime.now()),
        marks: (j['marks'] as num?)?.toDouble(),
        feedback: j['feedback']?.toString(),
        gradedAt: ApiClient.parseDate(j['gradedAt']),
        fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
        late: j['late'] == true,
      );

  bool get isGraded => marks != null;
  bool get hasFiles => fileCount > 0;
}

class Assignment {
  final String id;
  final String classId;
  final String classLabel;
  final String title;
  final String? instructions;
  final DateTime dueAt;
  final int? maxMarks;
  final bool allowResubmission;
  final String createdByName;
  final int instructionFileCount;
  final int? submissionCount;
  final List<AssignmentSubmission> mySubmissions;

  const Assignment({
    required this.id,
    required this.classId,
    required this.classLabel,
    required this.title,
    required this.dueAt,
    required this.allowResubmission,
    required this.createdByName,
    this.instructions,
    this.maxMarks,
    this.instructionFileCount = 0,
    this.submissionCount,
    this.mySubmissions = const [],
  });

  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
        id: j['id'].toString(),
        classId: (j['classId'] ?? '').toString(),
        classLabel: (j['classLabel'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        instructions: j['instructions']?.toString(),
        dueAt: ApiClient.parseDateOr(j['dueAt'], DateTime.now()),
        maxMarks: (j['maxMarks'] as num?)?.toInt(),
        allowResubmission: j['allowResubmission'] != false,
        createdByName: (j['createdByName'] ?? '').toString(),
        instructionFileCount: (j['instructionFileCount'] as num?)?.toInt() ?? 0,
        submissionCount: (j['submissionCount'] as num?)?.toInt(),
        mySubmissions: ((j['mySubmissions'] as List?) ?? const [])
            .map((e) =>
                AssignmentSubmission.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  /// Uses the device clock; the server re-checks the deadline on every write.
  bool get isOpen => dueAt.isAfter(DateTime.now());

  AssignmentSubmission? submissionFor(String studentId) {
    for (final s in mySubmissions) {
      if (s.studentId == studentId) return s;
    }
    return null;
  }
}

class AssignmentService {
  final ApiClient _api;
  AssignmentService({ApiClient? api}) : _api = api ?? ApiClient();

  static const topic = 'assignments';

  Future<List<Assignment>> list({String? classId}) async {
    final res = await _api.get(classId == null
        ? '/assignments'
        : '/assignments?classId=${Uri.encodeComponent(classId)}');
    return (res as List)
        .map((e) => Assignment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Stream<List<Assignment>> watch({String? classId}) =>
      liveQuery(topic, () => list(classId: classId),
          pollEvery: const Duration(minutes: 2));

  Future<String> create({
    required String classId,
    required String title,
    String? instructions,
    required DateTime dueAt,
    int? maxMarks,
    bool allowResubmission = true,
  }) async {
    final res = await _api.post('/assignments', {
      'classId': classId,
      'title': title.trim(),
      if (instructions != null && instructions.trim().isNotEmpty)
        'instructions': instructions.trim(),
      'dueAt': dueAt.toUtc().toIso8601String(),
      if (maxMarks != null) 'maxMarks': maxMarks,
      'allowResubmission': allowResubmission,
    });
    DataChanges.notify(topic);
    return (res as Map)['id'].toString();
  }

  Future<void> delete(String id) async {
    await _api.delete('/assignments/$id');
    DataChanges.notify(topic);
  }

  Future<(int, List<AssignmentSubmission>)> submissions(String id) async {
    final res = Map<String, dynamic>.from(
        await _api.get('/assignments/$id/submissions') as Map);
    return (
      (res['enrolledCount'] as num?)?.toInt() ?? 0,
      ((res['submissions'] as List?) ?? const [])
          .map((e) =>
              AssignmentSubmission.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// Creates or updates the signed-in student's submission; returns its id.
  Future<String> submit(String assignmentId, {String? note}) async {
    final res = await _api.post('/assignments/$assignmentId/submission',
        {if (note != null) 'note': note});
    DataChanges.notify(topic);
    return (res as Map)['id'].toString();
  }

  Future<void> grade(String assignmentId, String submissionId,
      {required double marks, String? feedback}) async {
    await _api.put('/assignments/$assignmentId/submissions/$submissionId/grade',
        {'marks': marks, if (feedback != null) 'feedback': feedback});
    DataChanges.notify(topic);
  }
}
