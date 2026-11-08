import '../remote/api_client.dart';

/// A point-in-time snapshot of one class+section's attendance and fee
/// standing, generated on demand by an admin and kept until deleted.
class ClassReportModel {
  final String id;
  final String academyId;
  final String classLabel;
  final DateTime generatedAt;
  final int totalStudents;
  final int present;
  final int absent;
  final int feePaid;
  final int feePending;
  final double feePaidAmount;
  final double feePendingAmount;

  const ClassReportModel({
    required this.id,
    required this.academyId,
    required this.classLabel,
    required this.generatedAt,
    required this.totalStudents,
    required this.present,
    required this.absent,
    required this.feePaid,
    required this.feePending,
    required this.feePaidAmount,
    required this.feePendingAmount,
  });

  Map<String, dynamic> toMap() => {
        'academy_id': academyId,
        'class_label': classLabel,
        'generated_at': generatedAt.toUtc().toIso8601String(),
        'total_students': totalStudents,
        'present': present,
        'absent': absent,
        'fee_paid': feePaid,
        'fee_pending': feePending,
        'fee_paid_amount': feePaidAmount,
        'fee_pending_amount': feePendingAmount,
      };

  factory ClassReportModel.fromMap(String id, Map<String, dynamic> map) {
    return ClassReportModel(
      id: id,
      academyId: (map['academy_id'] ?? '').toString(),
      classLabel: (map['class_label'] ?? '').toString(),
      generatedAt: ApiClient.parseRequiredDate(map['generated_at'],
          field: 'generated_at'),
      totalStudents: _int(map['total_students']),
      present: _int(map['present']),
      absent: _int(map['absent']),
      feePaid: _int(map['fee_paid']),
      feePending: _int(map['fee_pending']),
      feePaidAmount: _double(map['fee_paid_amount']),
      feePendingAmount: _double(map['fee_pending_amount']),
    );
  }

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  static double _double(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
}
