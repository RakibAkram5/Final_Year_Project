import '../models/app_user.dart';
import '../models/class_entity.dart';
import '../remote/api_client.dart';
import '../remote/live_query.dart';

class ClassRepository {
  final ApiClient _api = ApiClient();

  ClassRepository({dynamic db});

  /// Classes visible to the caller (the server scopes by role).
  Future<List<ClassEntity>> fetchAll() async {
    final res = await _api.get('/classes');
    final classes = (res as List)
        .map((item) => ClassEntity.fromMap(
            (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
        .toList();
    classes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return classes;
  }

  Stream<List<ClassEntity>> watchAll(String academyId) =>
      liveQuery(DataTopics.classes, fetchAll);

  Stream<List<ClassEntity>> watchForTeacher(
          String teacherUid, String academyId) =>
      liveQuery(DataTopics.classes, () async {
        final all = await fetchAll();
        return all.where((c) => c.primaryTeacherId == teacherUid).toList();
      });

  Stream<List<ClassEntity>> watchForStudent(
          String studentUid, String academyId) =>
      liveQuery(DataTopics.classes, () async {
        final all = await fetchAll();
        return all.where((c) => c.studentIds.contains(studentUid)).toList();
      });

  /// Returns the class, or null if it is not visible to the caller.
  /// Network errors are thrown, not reported as "not found".
  Future<ClassEntity?> getById(String id) async {
    for (final c in await fetchAll()) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<String> createClass({
    required String className,
    required String section,
    required String subject,
    required AppUser teacher,
    required List<AppUser> students,
    required String academyId,
  }) async {
    final res = await _api.post('/classes', {
      'className': className.trim(),
      'section': section.trim(),
      'subject': subject.trim(),
      'primaryTeacherId': teacher.uid,
      'studentIds': students.map((s) => s.uid).toList(),
    });
    DataChanges.notify(DataTopics.classes);
    return (res['id'] ?? '').toString();
  }

  Future<void> deleteClass(String classId, String academyId) async {
    await _api.delete('/classes/$classId');
    DataChanges.notify(DataTopics.classes);
  }

  Future<void> updateClassEnrollment({
    required String classId,
    required List<AppUser> students,
  }) async {
    final current = await getById(classId);
    if (current == null) {
      throw ApiException('Class not found.', statusCode: 404);
    }
    final currentIds = current.studentIds;
    final targetIds = students.map((s) => s.uid).toSet();

    for (final s in students) {
      if (!currentIds.contains(s.uid)) {
        await _api.post('/classes/$classId/enroll', {'studentId': s.uid});
      }
    }
    for (final id in currentIds) {
      if (!targetIds.contains(id)) {
        await _api.delete('/classes/$classId/enroll/$id');
      }
    }
    DataChanges.notify(DataTopics.classes);
  }

  Future<void> updateClassDetails({
    required String classId,
    String? className,
    String? section,
    String? subject,
    AppUser? teacher,
  }) async {
    final payload = <String, dynamic>{};
    if (className != null && className.trim().isNotEmpty) {
      payload['className'] = className.trim();
    }
    if (section != null && section.trim().isNotEmpty) {
      payload['section'] = section.trim();
    }
    if (subject != null && subject.trim().isNotEmpty) {
      payload['subject'] = subject.trim();
    }
    if (teacher != null) {
      payload['primaryTeacherId'] = teacher.uid;
    }
    if (payload.isNotEmpty) {
      await _api.put('/classes/$classId', payload);
      DataChanges.notify(DataTopics.classes);
    }
  }

  Future<void> updateClassTeacher({
    required String classId,
    required AppUser teacher,
  }) async {
    await _api.put('/classes/$classId', {
      'primaryTeacherId': teacher.uid,
    });
    DataChanges.notify(DataTopics.classes);
  }
}
