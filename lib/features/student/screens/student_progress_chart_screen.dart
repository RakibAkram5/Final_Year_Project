import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/test_mark_model.dart';

class StudentProgressChartScreen extends StatefulWidget {
  final String studentUid;
  const StudentProgressChartScreen({super.key, required this.studentUid});

  @override
  State<StudentProgressChartScreen> createState() =>
      _StudentProgressChartScreenState();
}

class _StudentProgressChartScreenState
    extends State<StudentProgressChartScreen> {
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
        title: const Text('Performance Analytics',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(context),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildStudentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Performance Analytics',
      titleIcon: Icons.show_chart_rounded,
      navSections: navSections,
      activeNavId: 'progress_charts',
      user: Provider.of<AuthProvider>(context).currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final academyId = user?.academyId ?? '';

    return academyId.isEmpty
        ? Center(
            child: Text("Session error",
                style: TextStyle(color: context.appColors.textSecondary)))
        : StreamBuilder<List<TestMarkModel>>(
            stream: context
                .read<QuizProvider>()
                .watchStudentResults(widget.studentUid, academyId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent));
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading results: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                );
              }

              final results = snapshot.data ?? [];
              if (results.isEmpty) return _buildEmptyState();

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsRow(results),
                    const SizedBox(height: 32),
                    Text("PROGRESS TREND",
                        style: TextStyle(
                            color: context.appColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    _buildLineChart(results),
                    const SizedBox(height: 32),
                    Text("SUBJECT WISE PERFORMANCE",
                        style: TextStyle(
                            color: context.appColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    _buildSubjectBarChart(results),
                    const SizedBox(height: 40),
                  ],
                ),
              );
            },
          );
  }

  /// Chart-safe percentage (0-100 ke andar)
  double _pct(TestMarkModel r) => r.percentage.clamp(0.0, 100.0);

  Widget _buildStatsRow(List<TestMarkModel> results) {
    final avg = results.map(_pct).reduce((a, b) => a + b) / results.length;
    final highest = results.map(_pct).reduce((a, b) => a > b ? a : b);

    return Row(
      children: [
        _statItem("Average", "${avg.toStringAsFixed(1)}%", AppColors.accent),
        const SizedBox(width: 12),
        _statItem(
            "Highest", "${highest.toStringAsFixed(1)}%", AppColors.success),
        const SizedBox(width: 12),
        _statItem("Tests", "${results.length}", AppColors.warning),
      ],
    );
  }

  Widget _statItem(String label, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: context.appColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(val,
                  style: TextStyle(
                      color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<TestMarkModel> results) {
    final sortedResults = List<TestMarkModel>.from(results)
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

    final spots = sortedResults
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), _pct(e.value)))
        .toList();

    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(8, 24, 24, 10),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (value) => FlLine(
                color: context.appColors.border.withValues(alpha: 0.2),
                strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 25,
                getTitlesWidget: (val, meta) => Text("${val.toInt()}%",
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 10)),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: AppColors.accent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.2),
                    AppColors.accent.withValues(alpha: 0)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectBarChart(List<TestMarkModel> results) {
    final Map<String, List<double>> subjectData = {};
    for (var r in results) {
      subjectData.putIfAbsent(r.subject, () => []).add(_pct(r));
    }

    final subjects = subjectData.keys.toList();
    final List<BarChartGroupData> barGroups = [];

    for (int i = 0; i < subjects.length; i++) {
      final scores = subjectData[subjects[i]] ?? [];
      if (scores.isEmpty) continue;
      final avg = scores.reduce((a, b) => a + b) / scores.length;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: avg,
              color: AppColors.accent,
              width: 18,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
              backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 100,
                  color: context.appColors.border.withValues(alpha: 0.1)),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 280,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 8),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barGroups: barGroups,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          maxY: 100,
          titlesData: FlTitlesData(
            show: true,
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: 25,
                getTitlesWidget: (val, meta) => Text("${val.toInt()}",
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx >= 0 && idx < subjects.length) {
                    final subName = subjects[idx];
                    // Safe substring: check length first
                    final label = subName.length > 3
                        ? subName.substring(0, 3).toUpperCase()
                        : subName.toUpperCase();
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 8,
                      child: Text(label,
                          style: TextStyle(
                              color: context.appColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded,
              size: 64, color: context.appColors.textMuted),
          const SizedBox(height: 16),
          Text("No performance data available yet.",
              style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }
}
