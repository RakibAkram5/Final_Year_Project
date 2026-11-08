import '../models/attendance_record.dart';
import '../remote/api_client.dart';

class AttendanceRepository {
  final ApiClient _api = ApiClient();

  /// Saves (upserts) one class's attendance for a single day. The server
  /// enforces one record per student/class/day, so re-saving updates in
  /// place instead of duplicating.
  Future<void> saveAll(List<AttendanceRecord> records) async {
    if (records.isEmpty) return;
    final first = records.first;
    final payload = {
      'classId': first.classId,
      'logDate': ApiClient.dateOnly(first.logDate),
      'records': records
          .map((r) => {
                'studentId': r.studentId,
                'status': r.status,
              })
          .toList(),
    };
    await _api.post('/attendance/mark', payload);
  }

  List<AttendanceRecord> _parse(dynamic res) => (res as List)
      .map((item) => AttendanceRecord.fromMap(
          (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
      .toList();

  /// Throws on failure so the marking screen never mistakes an outage for
  /// "no attendance taken yet".
  Future<List<AttendanceRecord>> forClassOnDate({
    required String classId,
    required DateTime date,
    required String academyId,
  }) async {
    final key = ApiClient.dateOnly(date);
    final res = await _api.get(
        '/attendance/class?classId=${Uri.encodeComponent(classId)}&logDate=$key');
    return _parse(res);
  }

  /// Every attendance record the caller may see (the server scopes by role:
  /// admin = academy, teacher = own classes, parent = linked children,
  /// student = self). Optional filters narrow the range server-side.
  Future<List<AttendanceRecord>> getAllForAcademy(
    String academyId, {
    String? classId,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = <String>[
      if (classId != null) 'classId=${Uri.encodeComponent(classId)}',
      if (from != null) 'from=${ApiClient.dateOnly(from)}',
      if (to != null) 'to=${ApiClient.dateOnly(to)}',
    ];
    final res = await _api
        .get(query.isEmpty ? '/attendance' : '/attendance?${query.join('&')}');
    return _parse(res);
  }

  Stream<List<AttendanceRecord>> watchForStudent(
      String studentId, String academyId) async* {
    final res = await _api.get('/attendance/student/$studentId');
    yield _parse(res);
  }
}
