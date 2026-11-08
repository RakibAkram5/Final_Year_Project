import '../models/fee_challan_model.dart';
import '../remote/api_client.dart';

class FeeChallanRepository {
  final ApiClient _api = ApiClient();
  FeeChallanRepository({dynamic db});

  Future<void> createChallan(FeeChallanModel challan) async {
    await _api.post('/fees/challans', {
      'studentId': challan.studentId,
      'classLabel': challan.classLabel,
      'rollNumber': challan.rollNumber,
      'monthlyFee': challan.monthlyFee,
      'admissionFee': challan.admissionFee,
      'examFee': challan.examFee,
      'transportFee': challan.transportFee,
      'fine': challan.fine,
      'dueDate': ApiClient.dateOnly(challan.dueDate),
      'billingPeriod': challan.billingPeriod,
    });
  }

  /// Throws on network/authorization errors so screens can show them
  /// instead of an misleading empty state.
  Future<List<FeeChallanModel>> getForStudent(
      String studentId, String academyId) async {
    final res = await _api.get('/fees/challans/student/$studentId');
    return (res as List)
        .map((item) => FeeChallanModel.fromMap(
            (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<FeeChallanModel>> getAll(String academyId) async {
    final response = await _api.get('/fees/challans');
    return (response as List)
        .map((item) => FeeChallanModel.fromMap(
            (item['id'] ?? '').toString(), Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<FeeChallanModel?> getLatestForStudent(
      String studentId, String academyId,
      {String? month}) async {
    final list = await getForStudent(studentId, academyId);
    return _latestMatching(list, month);
  }

  FeeChallanModel? _latestMatching(List<FeeChallanModel> list, String? month) {
    if (list.isEmpty) return null;
    final sorted = [...list]..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    if (month == null || month.isEmpty) return sorted.first;
    final target = month.contains('-')
        ? month
        : '${DateTime.now().year}-${_monthNumber(month)}';
    for (final challan in sorted) {
      final period = challan.billingPeriod.isNotEmpty
          ? challan.billingPeriod
          : '${challan.dueDate.year}-${challan.dueDate.month.toString().padLeft(2, '0')}';
      if (period == target) return challan;
    }
    return null;
  }

  String _monthNumber(String month) {
    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    final index = months.indexOf(month.toLowerCase());
    return index < 0 ? '00' : (index + 1).toString().padLeft(2, '0');
  }

  Future<Map<String, FeeChallanModel?>> getLatestForStudents(
      List<String> studentIds, String academyId,
      {String? month}) async {
    // Admin-only screen: one academy-wide request instead of one per student.
    final all = await getAll(academyId);
    final byStudent = <String, List<FeeChallanModel>>{};
    for (final challan in all) {
      byStudent.putIfAbsent(challan.studentId, () => []).add(challan);
    }
    return {
      for (final id in studentIds)
        id: _latestMatching(byStudent[id] ?? const [], month),
    };
  }

  Future<void> updateStatus(String id, String status) async {
    if (status.toLowerCase() != 'paid') {
      throw UnsupportedError(
          'Only marking a challan as paid is supported by the server.');
    }
    await _api.put('/fees/challans/$id/pay', {});
  }
}
