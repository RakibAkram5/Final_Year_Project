import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../logic/auth_provider.dart';
import '../../logic/member_provider.dart';
import '../../logic/admin_ai_provider.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';
import 'fee_ledger_screen.dart';
import 'admin_quiz_list_screen.dart';

class AdminAiPredictionScreen extends StatefulWidget {
  const AdminAiPredictionScreen({super.key});

  @override
  State<AdminAiPredictionScreen> createState() =>
      _AdminAiPredictionScreenState();
}

class _AdminAiPredictionScreenState extends State<AdminAiPredictionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user?.academyId != null) {
        final academyId = user!.academyId!;
        context.read<MemberProvider>().load(academyId);
        context.read<AdminAiProvider>().runAcademyAnalysis(academyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Insights & Predictions',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'AI Insights & Predictions',
      titleIcon: Icons.auto_awesome_rounded,
      navSections: navSections,
      activeNavId: 'ai_prediction',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(),
    );
  }

  Widget _body() {
    return Consumer<AdminAiProvider>(
      builder: (context, ai, _) {
        if (ai.loading) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (ai.error != null) ...[
              _aiErrorBanner(ai.error!),
              const SizedBox(height: 20),
            ],
            _aiStatusHeader(),
            const SizedBox(height: 24),
            _buildRiskPrediction(ai),
            const SizedBox(height: 20),
            _buildFeeDelayRiskPrediction(ai),
            const SizedBox(height: 20),
            _buildRevenueForecast(ai),
            const SizedBox(height: 20),
            _buildPerformanceForecast(ai),
            const SizedBox(height: 20),
            _buildAcademicInsights(ai),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Widget _aiErrorBanner(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Insights may be incomplete — some data failed to load.",
              style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiStatusHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome,
              color: context.appColors.accentText, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "ACADEMY INSIGHTS",
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1),
            ),
          ),
          const Icon(Icons.bolt_rounded, color: AppColors.success, size: 16),
        ],
      ),
    );
  }

  Widget _buildRiskPrediction(AdminAiProvider ai) {
    final bool hasRisk = ai.atRiskCount > 0;
    return _predictionCard(
      title: "Rule-Based Student Success Screening",
      prediction: hasRisk
          ? "${ai.atRiskCount} Students at Risk"
          : "All Students Performing Well",
      insight: hasRisk
          ? "The following students need attention: ${ai.atRiskStudentNames.join(', ')}."
          : "Average academy performance is at ${ai.academyAvgPerformance.toStringAsFixed(1)}%. No major risks detected.",
      icon: Icons.person_search_rounded,
      color: hasRisk ? AppColors.warning : AppColors.success,
      actionLabel: "VIEW DETAILS",
      onAction: () => _showAtRiskDialog(context, ai),
    );
  }

  void _showAtRiskDialog(BuildContext context, AdminAiProvider ai) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: Text("At-Risk Students",
            style: TextStyle(color: context.appColors.textPrimary)),
        content: ai.atRiskCount > 0
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: ai.atRiskStudentNames
                    .map((name) => ListTile(
                          leading: const Icon(Icons.person,
                              color: AppColors.warning),
                          title: Text(name,
                              style: TextStyle(
                                  color: context.appColors.textPrimary)),
                        ))
                    .toList(),
              )
            : Text("All students are performing above the 50% threshold.",
                style: TextStyle(color: context.appColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("CLOSE")),
        ],
      ),
    );
  }

  /// Human-readable model state (the API returns machine codes).
  static String mlStatusLabel(String status) => switch (status) {
        'PRODUCTION' => 'Validated model active',
        'READY_TO_TRAIN' => 'Enough data – ready to train',
        'INSUFFICIENT_DATA' => 'Not enough data yet',
        'TRAINING' => 'Training in progress…',
        'TRAINING_FAILED' => 'Training failed',
        'VALIDATED' => 'Trained, not promoted',
        _ => 'ML service not available',
      };

  Widget _buildFeeDelayRiskPrediction(AdminAiProvider ai) {
    final status = ai.feeModel['status']?.toString() ?? 'NOT_READY';
    final records = ai.feeModel['usable_records'];
    final metadata = ai.feeModel['metadata'] as Map?;
    final validation = metadata?['metrics']?['metrics'];
    return _predictionCard(
      title: "Fee Payment Risk Model",
      prediction: mlStatusLabel(status),
      insight: status == 'PRODUCTION'
          ? "${ai.feePrediction == null ? 'Live scoring is unavailable.' : 'Scored ${ai.feePrediction?['scored'] ?? 0} students; risk counts: ${ai.feePrediction?['risk_counts'] ?? {}}; average risk ${ai.feePrediction?['average_probability'] ?? 'n/a'}. Probabilities are not calibrated.'} Version ${ai.feeModel['version'] ?? ''}; records: ${metadata?['records'] ?? 'unknown'}; validation ROC-AUC ${validation?['roc_auc'] ?? 'n/a'}, precision ${validation?['precision'] ?? 'n/a'}, recall ${validation?['recall'] ?? 'n/a'}, F1 ${validation?['f1'] ?? 'n/a'}; trained ${metadata?['trained_at'] ?? 'date unavailable'}. Metrics come from this academy's own records, including any labelled demo/test data.${ai.feeModel['last_training_error'] == null ? '' : ' Last training error: ${ai.feeModel['last_training_error']}'}"
          : "${records == null ? ai.feeModel['reason'] ?? 'ML service unavailable or not configured.' : '$records of ${ai.feeModel['minimum_records'] ?? 100} required labelled fee records are eligible for training.'} Predictions stay disabled until a validated model is promoted.",
      icon: Icons.warning_amber_rounded,
      color: status == 'PRODUCTION' ? AppColors.success : AppColors.warning,
      actionLabel: ai.training ? "TRAINING" : "TRAIN / RETRAIN",
      onAction: ai.training ? () {} : ai.trainModels,
    );
  }

  Widget _buildRevenueForecast(AdminAiProvider ai) {
    final double pending = ai.pendingAmount;
    final double predicted =
        pending * 0.85; // Heuristic: 85% usually pay on time

    return _predictionCard(
      title: "Revenue Estimate (Heuristic)",
      prediction: "Predicted Rs. ${predicted.toStringAsFixed(0)}",
      insight:
          "Uses a fixed 85% collection assumption on Rs. ${pending.toStringAsFixed(0)} pending fees; this is not an ML prediction.",
      icon: Icons.payments_rounded,
      color: AppColors.success,
      actionLabel: "LEDGER",
      onAction: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const FeeLedgerScreen())),
    );
  }

  Widget _buildPerformanceForecast(AdminAiProvider ai) {
    final status = ai.performanceModel['status']?.toString() ?? 'NOT_READY';
    final records = ai.performanceModel['usable_records'];
    final metadata = ai.performanceModel['metadata'] as Map?;
    final validation = metadata?['metrics']?['metrics'];
    return _predictionCard(
      title: "Academic Performance Model",
      prediction: mlStatusLabel(status),
      insight: status == 'PRODUCTION'
          ? "${ai.performancePrediction == null ? 'Live scoring is unavailable.' : 'Scored ${ai.performancePrediction?['scored'] ?? 0} subject groups; predicted average marks ${ai.performancePrediction?['average_predicted_marks'] ?? 'n/a'}. '}Version ${ai.performanceModel['version'] ?? ''}; records: ${metadata?['records'] ?? 'unknown'}; validation MAE ${validation?['mae'] ?? 'n/a'}, RMSE ${validation?['rmse'] ?? 'n/a'}, R² ${validation?['r2'] ?? 'n/a'}; trained ${metadata?['trained_at'] ?? 'date unavailable'}. Metrics come from this academy's own records, including any labelled demo/test data.${ai.performanceModel['last_training_error'] == null ? '' : ' Last training error: ${ai.performanceModel['last_training_error']}'}"
          : "${records == null ? ai.performanceModel['reason'] ?? 'ML service unavailable or not configured.' : '$records of ${ai.performanceModel['minimum_records'] ?? 100} required dated assessment records are eligible for training.'} No forecast is shown until a validated model is promoted.",
      icon: Icons.trending_up_rounded,
      color: status == 'PRODUCTION' ? AppColors.success : AppColors.warning,
      actionLabel: ai.training ? "TRAINING" : "TRAIN / RETRAIN",
      onAction: ai.training ? () {} : ai.trainModels,
    );
  }

  Widget _buildAcademicInsights(AdminAiProvider ai) {
    return _predictionCard(
      title: "Subject Strength Analysis",
      prediction: "Weakest Area: ${ai.weakestSubject}",
      insight:
          "Academy-wide average marks in ${ai.weakestSubject} are currently the lowest across all subjects.",
      icon: Icons.analytics_rounded,
      color: AppColors.accent,
      actionLabel: "REPORTS",
      onAction: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AdminQuizListScreen())),
    );
  }

  Widget _predictionCard({
    required String title,
    required String prediction,
    required String insight,
    required IconData icon,
    required Color color,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(prediction,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(insight,
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 13,
                  height: 1.4)),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onAction,
              child: Text(actionLabel,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
