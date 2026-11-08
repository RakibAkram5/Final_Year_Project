import '../models/class_report_model.dart';
import '../remote/api_client.dart';
import '../remote/live_query.dart';

/// Class reports are generated server-side from real attendance and fee
/// records (`POST /class-reports`), so the client cannot persist made-up
/// figures.
class ClassReportRepository {
  final ApiClient _api = ApiClient();
  ClassReportRepository({dynamic db});

  Future<List<ClassReportModel>> fetchAll() async {
    final res = await _api.get('/class-reports');
    return (res as List)
        .map((item) => ClassReportModel.fromMap(
            (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
  }

  Stream<List<ClassReportModel>> watchAll(String academyId) =>
      liveQuery(DataTopics.classReports, fetchAll);

  /// Generates and stores a snapshot for [sectionId]. [asOf] is the
  /// caller's local calendar day used for "today's" attendance.
  Future<ClassReportModel> generate({
    required String sectionId,
    DateTime? asOf,
  }) async {
    final res = await _api.post('/class-reports', {
      'sectionId': sectionId,
      'logDate': ApiClient.dateOnly(asOf ?? DateTime.now()),
    });
    DataChanges.notify(DataTopics.classReports);
    return ClassReportModel.fromMap(
        (res['id'] ?? '').toString(), Map<String, dynamic>.from(res as Map));
  }

  Future<void> delete(String id) async {
    await _api.delete('/class-reports/$id');
    DataChanges.notify(DataTopics.classReports);
  }
}
