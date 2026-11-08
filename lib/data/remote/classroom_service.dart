import '../models/shared_resource.dart';
import '../models/student_query.dart';
import 'api_client.dart';
import 'live_query.dart';

/// Classroom resources and student questions over REST (`/resources`,
/// `/queries`). The server enforces class membership: teachers see their
/// classes, students only classes they are enrolled in.
class ClassroomService {
  final ApiClient _api = ApiClient();

  // --- Shared Resources ---
  Future<void> uploadResource(SharedResource res) async {
    await _api.post('/resources', res.toApiBody());
    DataChanges.notify(DataTopics.resources);
  }

  Future<void> deleteResource(String id) async {
    await _api.delete('/resources/$id');
    DataChanges.notify(DataTopics.resources);
  }

  Stream<List<SharedResource>> watchResources(
          String classId, String academyId) =>
      liveQuery(DataTopics.resources, () async {
        final response = await _api
            .get('/resources?classId=${Uri.encodeComponent(classId)}');
        return (response as List)
            .map((d) => SharedResource.fromMap((d['id'] ?? '').toString(),
                Map<String, dynamic>.from(d as Map)))
            .toList();
      });

  // --- Student Queries ---
  Future<void> postQuery(StudentQuery query) async {
    await _api.post('/queries', {
      'classId': query.classId,
      'question': query.question,
    });
    DataChanges.notify(DataTopics.queries);
  }

  Future<void> answerQuery(String queryId, String answer) async {
    await _api.put('/queries/$queryId/answer', {
      'answer': answer,
    });
    DataChanges.notify(DataTopics.queries);
  }

  Future<List<StudentQuery>> _queries(String path) async {
    final response = await _api.get(path);
    return (response as List)
        .map((d) => StudentQuery.fromMap(
            (d['id'] ?? '').toString(), Map<String, dynamic>.from(d as Map)))
        .toList();
  }

  Stream<List<StudentQuery>> watchQueriesForClass(
          String classId, String academyId) =>
      liveQuery(DataTopics.queries,
          () => _queries('/queries?classId=${Uri.encodeComponent(classId)}'),
          pollEvery: const Duration(minutes: 1));

  Stream<List<StudentQuery>> watchQueriesForTeacher(
          String teacherId, String academyId) =>
      liveQuery(
          DataTopics.queries,
          () =>
              _queries('/queries?teacherId=${Uri.encodeComponent(teacherId)}'),
          pollEvery: const Duration(minutes: 1));
}
