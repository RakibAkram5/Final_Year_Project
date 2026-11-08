import '../models/app_user.dart';
import '../models/class_section.dart';
import '../remote/api_client.dart';
import '../remote/live_query.dart';

/// Owns the canonical class+section roster (`/class-sections`).
///
/// Subject offerings (`/classes`) linked to a section mirror its roster on
/// the server, so enrolling a student happens exactly once per section
/// regardless of how many subjects or teachers are assigned to it.
class ClassSectionRepository {
  final ApiClient _api = ApiClient();

  // `db`/`classRepo` are accepted for source compatibility with older call
  // sites; all persistence now goes through the REST API.
  ClassSectionRepository({dynamic db, dynamic classRepo});

  // ---------- Reads ----------

  Future<List<ClassSectionEntity>> fetchAll() async {
    final res = await _api.get('/class-sections');
    final list = (res as List)
        .map((item) => ClassSectionEntity.fromMap(
            (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
        .toList();
    list.sort((a, b) {
      final byClass = a.className.compareTo(b.className);
      if (byClass != 0) return byClass;
      final byProgram = a.program.compareTo(b.program);
      return byProgram != 0 ? byProgram : a.section.compareTo(b.section);
    });
    return list;
  }

  /// Emits the academy's sections now and again after every local change.
  Stream<List<ClassSectionEntity>> watchAll(String academyId) =>
      liveQuery(DataTopics.classSections, fetchAll);

  // ---------- Writes ----------

  Future<String> createSection({
    required String academyId,
    required String className,
    String program = '',
    required String section,
    List<String> studentIds = const [],
  }) async {
    final res = await _api.post('/class-sections', {
      'className': className.trim(),
      'program': program.trim(),
      'section': section.trim(),
      if (studentIds.isNotEmpty) 'studentIds': studentIds,
    });
    _changed();
    return (res['id'] ?? '').toString();
  }

  /// Replaces the section roster; the server cascades it to every subject
  /// offering linked to the section in one transaction.
  Future<void> updateEnrollment({
    required ClassSectionEntity section,
    required List<AppUser> students,
  }) async {
    await _api.put('/class-sections/${section.id}/enrollment', {
      'studentIds': students.map((s) => s.uid).toList(),
    });
    _changed();
  }

  /// Adds one student (optionally with a roll number) to the section and to
  /// every subject offering linked to it.
  Future<void> enrollStudent({
    required String sectionId,
    required String studentId,
    String? rollNumber,
  }) async {
    await _api.post('/class-sections/$sectionId/enroll', {
      'studentId': studentId,
      if (rollNumber != null && rollNumber.trim().isNotEmpty)
        'rollNumber': rollNumber.trim(),
    });
    _changed();
  }

  Future<void> unenrollStudent({
    required String sectionId,
    required String studentId,
  }) async {
    await _api.delete('/class-sections/$sectionId/enroll/$studentId');
    _changed();
  }

  /// Deletes the section. Subject offerings are kept (unlinked) so their
  /// attendance, marks and timetable history are never lost.
  Future<void> deleteSection(ClassSectionEntity section) async {
    await _api.delete('/class-sections/${section.id}');
    _changed();
  }

  void _changed() {
    DataChanges.notify(DataTopics.classSections);
    DataChanges.notify(DataTopics.classes);
  }
}
