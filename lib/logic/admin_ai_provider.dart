import 'package:flutter/material.dart';
import '../data/models/test_mark_model.dart';
import '../data/repositories/fee_challan_repository.dart';
import '../data/remote/quiz_service.dart';
import '../data/remote/api_client.dart';

class AdminAiProvider extends ChangeNotifier {
  final QuizService _quizService = QuizService();
  final FeeChallanRepository _feeRepo = FeeChallanRepository();
  final ApiClient _api = ApiClient();

  bool _loading = false;
  String? _error;
  bool get loading => _loading;
  String? get error => _error;

  // Insights Data
  int _atRiskCount = 0;
  String _weakestSubject = "No Data";
  double _academyAvgPerformance = 0.0;
  List<String> _atRiskStudentNames = [];

  // Revenue Forecasting
  double _projectedRevenue = 0.0;
  double _collectionEfficiency = 0.0;
  int _pendingPaymentsCount = 0;
  double _pendingAmount = 0.0;

  int get atRiskCount => _atRiskCount;
  String get weakestSubject => _weakestSubject;
  double get academyAvgPerformance => _academyAvgPerformance;
  List<String> get atRiskStudentNames => _atRiskStudentNames;

  double get projectedRevenue => _projectedRevenue;
  double get collectionEfficiency => _collectionEfficiency;
  int get pendingPaymentsCount => _pendingPaymentsCount;
  double get pendingAmount => _pendingAmount;

  // ML predictions remain unavailable until a validated production artifact
  // exists; the dashboard consumes readiness and metrics instead.
  Map<String, dynamic> _feeModel = {'status': 'NOT_READY'};
  Map<String, dynamic> _performanceModel = {'status': 'NOT_READY'};
  Map<String, dynamic>? _feePrediction;
  Map<String, dynamic>? _performancePrediction;
  Map<String, dynamic> get feeModel => _feeModel;
  Map<String, dynamic> get performanceModel => _performanceModel;
  Map<String, dynamic>? get feePrediction => _feePrediction;
  Map<String, dynamic>? get performancePrediction => _performancePrediction;
  bool _training = false;
  bool get training => _training;

  Future<void> runAcademyAnalysis(String academyId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Run both analyses in parallel for THIS academy
      await Future.wait([
        _analyzePerformance(academyId),
        _analyzeRevenue(academyId),
        _loadMlStatus(),
      ]);
    } catch (e) {
      debugPrint("AI Analysis Error: $e");
      _error = 'Could not load insights: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadMlStatus() async {
    try {
      final result = await _api.get('/admin/ml/status');
      if (result is Map) {
        _feeModel = Map<String, dynamic>.from(result['fee_risk'] as Map? ?? {});
        _performanceModel =
            Map<String, dynamic>.from(result['performance'] as Map? ?? {});
        _feePrediction = null;
        _performancePrediction = null;
        final requests = <Future<void>>[];
        if (_feeModel['status'] == 'PRODUCTION') {
          requests.add(_loadPrediction('/admin/ml/predict/fee-risk', true));
        }
        if (_performanceModel['status'] == 'PRODUCTION') {
          requests.add(_loadPrediction('/admin/ml/predict/performance', false));
        }
        await Future.wait(requests);
      }
    } catch (_) {
      _feePrediction = null;
      _performancePrediction = null;
      _feeModel = {'status': 'NOT_READY', 'reason': 'ML service unavailable'};
      _performanceModel = {
        'status': 'NOT_READY',
        'reason': 'ML service unavailable'
      };
    }
  }

  Future<void> _loadPrediction(String endpoint, bool feeRisk) async {
    try {
      final value = await _api.post(endpoint, {});
      if (value is Map) {
        if (feeRisk) {
          _feePrediction = Map<String, dynamic>.from(value);
        } else {
          _performancePrediction = Map<String, dynamic>.from(value);
        }
      }
    } catch (_) {
      // Keep the validated model status visible, but do not invent a result.
    }
  }

  Future<void> trainModels() async {
    _training = true;
    _error = null;
    notifyListeners();
    try {
      // Training runs as a background job on the ML service; poll its status
      // instead of holding one long HTTP request open.
      await _api.post('/admin/ml/retrain', {});
      for (var i = 0; i < 60; i++) {
        await _loadMlStatus();
        final busy = _feeModel['status'] == 'TRAINING' ||
            _performanceModel['status'] == 'TRAINING';
        if (!busy) break;
        notifyListeners();
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _training = false;
      notifyListeners();
    }
  }

  Future<void> _analyzePerformance(String academyId) async {
    final allMarks = await _quizService.getAllAcademyMarks(academyId);
    if (allMarks.isEmpty) {
      _atRiskCount = 0;
      _weakestSubject = "No Data";
      _academyAvgPerformance = 0.0;
      _atRiskStudentNames = [];
    } else {
      _calculatePerformanceInsights(allMarks);
    }
  }

  Future<void> _analyzeRevenue(String academyId) async {
    final challans = await _feeRepo.getAll(academyId);
    if (challans.isEmpty) {
      _projectedRevenue = 0;
      _collectionEfficiency = 0;
      _pendingPaymentsCount = 0;
      _pendingAmount = 0;
      return;
    }
    final total =
        challans.fold<double>(0, (sum, item) => sum + item.totalAmount);
    final paid = challans
        .where((item) => item.isPaid)
        .fold<double>(0, (sum, item) => sum + item.totalAmount);
    _pendingPaymentsCount = challans.where((item) => !item.isPaid).length;
    _pendingAmount = total - paid;
    _collectionEfficiency = total > 0 ? paid / total * 100 : 0;
    _projectedRevenue = total;
  }

  // Legacy ledger forecast fields remain for compatibility. No ML-labelled
  // prediction is populated without an available validated production model.

  void _calculatePerformanceInsights(List<TestMarkModel> marks) {
    // 1. Average Academy Performance
    _academyAvgPerformance =
        marks.map((m) => m.percentage).reduce((a, b) => a + b) / marks.length;

    // 2. Risk Analysis (Average Percentage < 50%)
    final Map<String, List<double>> studentScores = {};
    final Map<String, String> studentNames = {};

    for (var m in marks) {
      studentScores.putIfAbsent(m.studentId, () => []).add(m.percentage);
      studentNames[m.studentId] = m.studentName;
    }

    _atRiskStudentNames.clear();
    studentScores.forEach((id, scores) {
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      if (avg < 50) {
        _atRiskStudentNames.add(studentNames[id]!);
      }
    });
    _atRiskCount = _atRiskStudentNames.length;

    // 3. Subject Weakness Analysis
    final Map<String, List<double>> subjectScores = {};
    for (var m in marks) {
      subjectScores.putIfAbsent(m.subject, () => []).add(m.percentage);
    }

    String weakest = "No Data";
    double lowestAvg = 101.0;

    subjectScores.forEach((sub, scores) {
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      if (avg < lowestAvg) {
        lowestAvg = avg;
        weakest = sub;
      }
    });

    _weakestSubject = weakest;
  }
}
