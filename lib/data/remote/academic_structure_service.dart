import '../models/academic_structure.dart';
import 'api_client.dart';
import 'live_query.dart';

/// REST-backed storage for each academy's configurable academic structure
/// (`/academic-structure`, stored on the academy row). The server returns
/// the defaults until an admin saves a custom structure, so no seeding
/// write is needed.
class AcademicStructureService {
  final ApiClient _api = ApiClient();

  Future<AcademicStructure> fetch() async {
    final res = await _api.get('/academic-structure');
    if (res is Map) return AcademicStructure.fromMap(res);
    return AcademicStructure.defaults;
  }

  /// Kept for call-site compatibility: reading never needs to seed.
  Future<AcademicStructure> getOrSeed(String academyId) => fetch();

  Stream<AcademicStructure> watch(String academyId) =>
      liveQuery(DataTopics.academicStructure, fetch);

  Future<void> update(String academyId, AcademicStructure structure) async {
    await _api.put('/academic-structure', structure.toMap());
    DataChanges.notify(DataTopics.academicStructure);
  }
}
