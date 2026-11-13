import 'api_client.dart';

/// Typed view of `GET /admin/ml/analytics`.
///
/// Every series is derived from the academy's own records; the model-based
/// sections are only `available` when the ML service reports a validated
/// production model. Nothing here invents a value: missing numbers stay null
/// so the dashboard can render an honest empty state.
class MlAnalytics {
  final DateTime? generatedAt;
  final AnalyticsFilters filters;
  final bool mlConfigured;
  final bool mlOk;
  final String? mlError;
  final Map<String, dynamic> models;
  final PerformanceSummary performance;
  final RevenueSummary revenue;
  final FeeRiskPrediction feeRisk;
  final PerformancePrediction performancePrediction;
  final List<AtRiskStudent> atRisk;
  final int atRiskThreshold;
  final String atRiskRule;
  final Map<String, String> errors;

  const MlAnalytics({
    required this.generatedAt,
    required this.filters,
    required this.mlConfigured,
    required this.mlOk,
    required this.mlError,
    required this.models,
    required this.performance,
    required this.revenue,
    required this.feeRisk,
    required this.performancePrediction,
    required this.atRisk,
    required this.atRiskThreshold,
    required this.atRiskRule,
    required this.errors,
  });

  String modelStatus(String key) =>
      (_map(models[key])['status'] ?? 'NOT_READY').toString();

  factory MlAnalytics.fromJson(Map<String, dynamic> json) {
    final services = _map(_map(json['services'])['ml']);
    final predictions = _map(json['predictions']);
    final atRisk = _map(json['at_risk']);
    return MlAnalytics(
      generatedAt: ApiClient.parseDate(json['generated_at']),
      filters: AnalyticsFilters.fromJson(_map(json['filters'])),
      mlConfigured: services['configured'] == true,
      mlOk: services['ok'] == true,
      mlError: services['error']?.toString(),
      models: _map(json['models']),
      performance: PerformanceSummary.fromJson(_map(json['performance'])),
      revenue: RevenueSummary.fromJson(_map(json['revenue'])),
      feeRisk: FeeRiskPrediction.fromJson(_map(predictions['fee_risk'])),
      performancePrediction:
          PerformancePrediction.fromJson(_map(predictions['performance'])),
      atRisk: _list(atRisk['students'])
          .map((e) => AtRiskStudent.fromJson(_map(e)))
          .toList(),
      atRiskThreshold: _int(atRisk['threshold']) ?? 50,
      atRiskRule: (atRisk['rule'] ?? '').toString(),
      errors:
          _map(json['errors']).map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }
}

class AnalyticsFilters {
  final String? from;
  final String? to;
  final String? sectionId;
  final String? level;
  final List<SectionOption> sections;
  final List<String> levels;
  final int studentsInScope;

  const AnalyticsFilters({
    this.from,
    this.to,
    this.sectionId,
    this.level,
    this.sections = const [],
    this.levels = const [],
    this.studentsInScope = 0,
  });

  factory AnalyticsFilters.fromJson(Map<String, dynamic> json) {
    final available = _map(json['available']);
    return AnalyticsFilters(
      from: json['from']?.toString(),
      to: json['to']?.toString(),
      sectionId: json['sectionId']?.toString(),
      level: json['level']?.toString(),
      sections: _list(available['sections'])
          .map((e) => SectionOption.fromJson(_map(e)))
          .toList(),
      levels: _list(available['levels']).map((e) => e.toString()).toList(),
      studentsInScope: _int(json['students_in_scope']) ?? 0,
    );
  }
}

class SectionOption {
  final String id;
  final String label;
  final int students;
  const SectionOption(
      {required this.id, required this.label, required this.students});
  factory SectionOption.fromJson(Map<String, dynamic> json) => SectionOption(
        id: (json['id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        students: _int(json['students']) ?? 0,
      );
}

class TrendPoint {
  final String month; // YYYY-MM
  final double? average;
  final double? predicted;
  final int count;
  final int students;
  const TrendPoint(
      {required this.month,
      this.average,
      this.predicted,
      this.count = 0,
      this.students = 0});
  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        month: (json['month'] ?? '').toString(),
        average: _double(json['average']),
        predicted: _double(json['predicted']),
        count: _int(json['count']) ?? 0,
        students: _int(json['students']) ?? 0,
      );
}

class LabelledAverage {
  final String label;
  final double? average;
  final int count;
  final int students;
  const LabelledAverage(
      {required this.label, this.average, this.count = 0, this.students = 0});
}

class PerformanceSummary {
  final int totalMarks;
  final int students;
  final double? academyAverage;
  final List<TrendPoint> trend;
  final List<LabelledAverage> classes;
  final List<LabelledAverage> subjects;

  const PerformanceSummary({
    this.totalMarks = 0,
    this.students = 0,
    this.academyAverage,
    this.trend = const [],
    this.classes = const [],
    this.subjects = const [],
  });

  factory PerformanceSummary.fromJson(Map<String, dynamic> json) =>
      PerformanceSummary(
        totalMarks: _int(json['total_marks']) ?? 0,
        students: _int(json['students']) ?? 0,
        academyAverage: _double(json['academy_average']),
        trend: _list(json['trend'])
            .map((e) => TrendPoint.fromJson(_map(e)))
            .toList(),
        classes: _list(json['classes']).map((e) {
          final m = _map(e);
          return LabelledAverage(
              label: (m['label'] ?? '').toString(),
              average: _double(m['average']),
              count: _int(m['count']) ?? 0,
              students: _int(m['students']) ?? 0);
        }).toList(),
        subjects: _list(json['subjects']).map((e) {
          final m = _map(e);
          return LabelledAverage(
              label: (m['subject'] ?? '').toString(),
              average: _double(m['average']),
              count: _int(m['count']) ?? 0);
        }).toList(),
      );
}

class RevenueMonth {
  final String period; // YYYY-MM
  final double billed;
  final double collected;
  final double pending;
  final double overdue;
  final int challans;
  final int paid;
  final double? collectionRate;
  const RevenueMonth({
    required this.period,
    this.billed = 0,
    this.collected = 0,
    this.pending = 0,
    this.overdue = 0,
    this.challans = 0,
    this.paid = 0,
    this.collectionRate,
  });
  factory RevenueMonth.fromJson(Map<String, dynamic> json) => RevenueMonth(
        period: (json['period'] ?? '').toString(),
        billed: _double(json['billed']) ?? 0,
        collected: _double(json['collected']) ?? 0,
        pending: _double(json['pending']) ?? 0,
        overdue: _double(json['overdue']) ?? 0,
        challans: _int(json['challans']) ?? 0,
        paid: _int(json['paid']) ?? 0,
        collectionRate: _double(json['collection_rate']),
      );
}

class RevenueEstimate {
  final double outstandingAmount;
  final int outstandingChallans;
  final double? historicalCollectionRate;
  final int historicalPeriods;
  final double? expectedCollectionHistorical;
  final double? expectedOnTimeModel;
  final double? modelScoredAmount;
  final int modelScoredChallans;
  final double? expectedBilledNextPeriod;
  final Map<String, String> basis;

  const RevenueEstimate({
    this.outstandingAmount = 0,
    this.outstandingChallans = 0,
    this.historicalCollectionRate,
    this.historicalPeriods = 0,
    this.expectedCollectionHistorical,
    this.expectedOnTimeModel,
    this.modelScoredAmount,
    this.modelScoredChallans = 0,
    this.expectedBilledNextPeriod,
    this.basis = const {},
  });

  factory RevenueEstimate.fromJson(Map<String, dynamic> json) =>
      RevenueEstimate(
        outstandingAmount: _double(json['outstanding_amount']) ?? 0,
        outstandingChallans: _int(json['outstanding_challans']) ?? 0,
        historicalCollectionRate: _double(json['historical_collection_rate']),
        historicalPeriods: _int(json['historical_periods']) ?? 0,
        expectedCollectionHistorical:
            _double(json['expected_collection_historical']),
        expectedOnTimeModel: _double(json['expected_on_time_model']),
        modelScoredAmount: _double(json['model_scored_amount']),
        modelScoredChallans: _int(json['model_scored_challans']) ?? 0,
        expectedBilledNextPeriod: _double(json['expected_billed_next_period']),
        basis:
            _map(json['basis']).map((k, v) => MapEntry(k, v?.toString() ?? '')),
      );
}

class RevenueSummary {
  final List<RevenueMonth> months;
  final RevenueEstimate estimate;
  final int totalChallans;
  const RevenueSummary(
      {this.months = const [],
      this.estimate = const RevenueEstimate(),
      this.totalChallans = 0});
  factory RevenueSummary.fromJson(Map<String, dynamic> json) => RevenueSummary(
        months: _list(json['months'])
            .map((e) => RevenueMonth.fromJson(_map(e)))
            .toList(),
        estimate: RevenueEstimate.fromJson(_map(json['estimate'])),
        totalChallans: _int(json['total_challans']) ?? 0,
      );
}

class FeeRiskStudent {
  final String studentId;
  final String studentName;
  final String classLabel;
  final double probability;
  final String riskCategory;
  final double outstanding;
  const FeeRiskStudent({
    required this.studentId,
    required this.studentName,
    required this.classLabel,
    required this.probability,
    required this.riskCategory,
    required this.outstanding,
  });
  factory FeeRiskStudent.fromJson(Map<String, dynamic> json) => FeeRiskStudent(
        studentId: (json['studentId'] ?? '').toString(),
        studentName: (json['studentName'] ?? 'Student').toString(),
        classLabel: (json['classLabel'] ?? '').toString(),
        probability: _double(json['probability']) ?? 0,
        riskCategory: (json['risk_category'] ?? '').toString(),
        outstanding: _double(json['outstanding']) ?? 0,
      );
}

class FeeRiskPrediction {
  final bool available;
  final String status;
  final String? reason;
  final String? version;
  final Map<String, dynamic> metrics;
  final DateTime? trainedAt;
  final int? records;
  final int scored;
  final Map<String, int> distribution;
  final double? averageProbability;
  final List<FeeRiskStudent> students;

  const FeeRiskPrediction({
    this.available = false,
    this.status = 'NOT_READY',
    this.reason,
    this.version,
    this.metrics = const {},
    this.trainedAt,
    this.records,
    this.scored = 0,
    this.distribution = const {},
    this.averageProbability,
    this.students = const [],
  });

  factory FeeRiskPrediction.fromJson(Map<String, dynamic> json) =>
      FeeRiskPrediction(
        available: json['available'] == true,
        status: (json['status'] ?? 'NOT_READY').toString(),
        reason: json['reason']?.toString(),
        version: json['version']?.toString(),
        metrics: _map(json['metrics']),
        trainedAt: ApiClient.parseDate(json['trained_at']),
        records: _int(json['records']),
        scored: _int(json['scored']) ?? 0,
        distribution:
            _map(json['distribution']).map((k, v) => MapEntry(k, _int(v) ?? 0)),
        averageProbability: _double(json['average_probability']),
        students: _list(json['students'])
            .map((e) => FeeRiskStudent.fromJson(_map(e)))
            .toList(),
      );
}

class ForecastRow {
  final String studentId;
  final String studentName;
  final String subject;
  final String classLabel;
  final int assessments;
  final double? latestActual;
  final double? priorAvg;
  final double? predictedNext;
  const ForecastRow({
    required this.studentId,
    required this.studentName,
    required this.subject,
    required this.classLabel,
    required this.assessments,
    this.latestActual,
    this.priorAvg,
    this.predictedNext,
  });
  factory ForecastRow.fromJson(Map<String, dynamic> json) => ForecastRow(
        studentId: (json['studentId'] ?? '').toString(),
        studentName: (json['studentName'] ?? 'Student').toString(),
        subject: (json['subject'] ?? '').toString(),
        classLabel: (json['classLabel'] ?? '').toString(),
        assessments: _int(json['assessments']) ?? 0,
        latestActual: _double(json['latest_actual']),
        priorAvg: _double(json['prior_avg']),
        predictedNext: _double(json['predicted_next']),
      );
}

class HoldoutRow {
  final String studentName;
  final String subject;
  final double actual;
  final double predicted;
  const HoldoutRow(
      {required this.studentName,
      required this.subject,
      required this.actual,
      required this.predicted});
  factory HoldoutRow.fromJson(Map<String, dynamic> json) => HoldoutRow(
        studentName: (json['studentName'] ?? 'Student').toString(),
        subject: (json['subject'] ?? '').toString(),
        actual: _double(json['actual']) ?? 0,
        predicted: _double(json['predicted']) ?? 0,
      );
}

class PerformancePrediction {
  final bool available;
  final String status;
  final String? reason;
  final String? version;
  final Map<String, dynamic> metrics;
  final DateTime? trainedAt;
  final int? records;
  final List<ForecastRow> forecast;
  final List<HoldoutRow> holdout;
  final int holdoutCount;
  final double? holdoutMae;
  final String? holdoutNote;
  final double? averagePredictedNext;

  const PerformancePrediction({
    this.available = false,
    this.status = 'NOT_READY',
    this.reason,
    this.version,
    this.metrics = const {},
    this.trainedAt,
    this.records,
    this.forecast = const [],
    this.holdout = const [],
    this.holdoutCount = 0,
    this.holdoutMae,
    this.holdoutNote,
    this.averagePredictedNext,
  });

  factory PerformancePrediction.fromJson(Map<String, dynamic> json) {
    final holdout = _map(json['holdout']);
    return PerformancePrediction(
      available: json['available'] == true,
      status: (json['status'] ?? 'NOT_READY').toString(),
      reason: json['reason']?.toString(),
      version: json['version']?.toString(),
      metrics: _map(json['metrics']),
      trainedAt: ApiClient.parseDate(json['trained_at']),
      records: _int(json['records']),
      forecast: _list(json['forecast'])
          .map((e) => ForecastRow.fromJson(_map(e)))
          .toList(),
      holdout: _list(holdout['rows'])
          .map((e) => HoldoutRow.fromJson(_map(e)))
          .toList(),
      holdoutCount: _int(holdout['count']) ?? 0,
      holdoutMae: _double(holdout['mae']),
      holdoutNote: holdout['note']?.toString(),
      averagePredictedNext: _double(json['average_predicted_next']),
    );
  }
}

class AtRiskStudent {
  final String studentId;
  final String studentName;
  final String classLabel;
  final List<String> reasons;
  final double? average;
  final double? predictedMin;
  final double? feeProbability;
  const AtRiskStudent({
    required this.studentId,
    required this.studentName,
    required this.classLabel,
    required this.reasons,
    this.average,
    this.predictedMin,
    this.feeProbability,
  });
  factory AtRiskStudent.fromJson(Map<String, dynamic> json) => AtRiskStudent(
        studentId: (json['studentId'] ?? '').toString(),
        studentName: (json['studentName'] ?? 'Student').toString(),
        classLabel: (json['classLabel'] ?? '').toString(),
        reasons: _list(json['reasons']).map((e) => e.toString()).toList(),
        average: _double(json['average']),
        predictedMin: _double(json['predicted_min']),
        feeProbability: _double(json['fee_probability']),
      );
}

/// Fetches the admin analytics dashboard with optional filters.
class MlAnalyticsService {
  final ApiClient _api;
  MlAnalyticsService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<MlAnalytics> fetch({
    String? from,
    String? to,
    String? sectionId,
    String? level,
  }) async {
    final query = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (sectionId != null && sectionId.isNotEmpty) 'sectionId': sectionId,
      if (level != null && level.isNotEmpty) 'level': level,
    };
    final suffix = query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final res = await _api.get('/admin/ml/analytics$suffix',
        timeout: const Duration(seconds: 90));
    return MlAnalytics.fromJson(Map<String, dynamic>.from(res as Map));
  }
}

// --- JSON helpers --------------------------------------------------------

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];

double? _double(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _int(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}
