import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/remote/ml_analytics_service.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

/// Admin ML analytics dashboard.
///
/// Every chart is drawn from this academy's own marks, challans and
/// attendance. Model-based series (forecast line, fee-risk scores, revenue
/// model estimate) appear only when the ML service reports a validated
/// production model; otherwise the section states plainly why it is empty.
class MlAnalyticsScreen extends StatefulWidget {
  const MlAnalyticsScreen({super.key});

  @override
  State<MlAnalyticsScreen> createState() => _MlAnalyticsScreenState();
}

class _MlAnalyticsScreenState extends State<MlAnalyticsScreen> {
  final _service = MlAnalyticsService();
  static final _money = NumberFormat('#,##0', 'en_US');
  static final _month = DateFormat('MMM yy');

  MlAnalytics? _data;
  bool _loading = true;
  String? _error;

  String? _sectionId;
  String? _level;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetch(
        sectionId: _sectionId,
        level: _level,
        from: _range == null ? null : _iso(_range!.start),
        to: _range == null ? null : _iso(_range!.end),
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _monthLabel(String yyyyMm) {
    final parsed = DateTime.tryParse('$yyyyMm-01');
    return parsed == null ? yyyyMm : _month.format(parsed);
  }

  static String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
  static String _rs(double? v) => v == null ? '—' : 'Rs. ${_money.format(v)}';

  // ---------------------------------------------------------------- shell --

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return WebAppShell(
        title: 'ML Analytics',
        titleIcon: Icons.insights_rounded,
        navSections: buildAdminNavSections(context,
            onDashboard: () =>
                Navigator.of(context).popUntil((r) => r.isFirst)),
        activeNavId: 'ml_analytics',
        user: context.watch<AuthProvider>().currentUser,
        onLogout: () => performWebLogout(context),
        body: _body(wide: true),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('ML Analytics',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: GradientBackground(child: SafeArea(child: _body(wide: false))),
    );
  }

  Widget _body({required bool wide}) {
    if (_loading && _data == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.warning, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? 'Could not load analytics.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again')),
          ]),
        ),
      );
    }
    final d = _data!;
    final children = <Widget>[
      _filters(d),
      if (_error != null) ...[
        const SizedBox(height: 10),
        _banner(_error!, AppColors.danger)
      ],
      if (!d.mlOk) ...[
        const SizedBox(height: 10),
        _banner(
            d.mlConfigured
                ? 'ML service unavailable right now (${d.mlError ?? 'no response'}). '
                    'Charts below use real records; model-based sections are hidden until it returns.'
                : 'ML service is not configured on the backend. Charts below use real '
                    'records only; forecasts and risk scores appear once it is connected.',
            AppColors.warning),
      ],
      const SizedBox(height: 14),
      _kpis(d),
      const SizedBox(height: 14),
      if (wide)
        _twoUp(_performanceTrendCard(d), _classComparisonCard(d))
      else ...[
        _performanceTrendCard(d),
        const SizedBox(height: 14),
        _classComparisonCard(d),
      ],
      const SizedBox(height: 14),
      if (wide)
        _twoUp(_subjectCard(d), _revenueCard(d))
      else ...[
        _subjectCard(d),
        const SizedBox(height: 14),
        _revenueCard(d),
      ],
      const SizedBox(height: 14),
      _revenueEstimateCard(d),
      const SizedBox(height: 14),
      if (wide)
        _twoUp(_feeRiskCard(d), _performanceForecastCard(d))
      else ...[
        _feeRiskCard(d),
        const SizedBox(height: 14),
        _performanceForecastCard(d),
      ],
      const SizedBox(height: 14),
      _atRiskCard(d),
      const SizedBox(height: 10),
      if (d.generatedAt != null)
        Text(
            'Generated ${DateFormat('dd MMM yyyy, HH:mm').format(d.generatedAt!.toLocal())}'
            ' · ${d.filters.studentsInScope} students in scope',
            style: TextStyle(color: context.appColors.textMuted, fontSize: 11)),
      const SizedBox(height: 30),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 4 : 16, 12, wide ? 4 : 16, 12),
        children: children,
      ),
    );
  }

  Widget _twoUp(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 14),
          Expanded(child: b),
        ],
      );

  // -------------------------------------------------------------- filters --

  Widget _filters(MlAnalytics d) {
    final colors = context.appColors;
    final sections = d.filters.sections;
    final levels = d.filters.levels;
    final rangeLabel = _range == null
        ? 'All dates'
        : '${DateFormat('dd MMM yy').format(_range!.start)} – ${DateFormat('dd MMM yy').format(_range!.end)}';
    return _card(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _dropdown<String?>(
            label: 'Class section',
            value: _sectionId,
            items: [
              const DropdownMenuItem(value: null, child: Text('All sections')),
              for (final s in sections)
                DropdownMenuItem(
                    value: s.id, child: Text('${s.label} (${s.students})')),
            ],
            onChanged: (v) {
              setState(() {
                _sectionId = v;
                if (v != null) _level = null;
              });
              _load();
            },
          ),
          _dropdown<String?>(
            label: 'Level / program',
            value: _level,
            items: [
              const DropdownMenuItem(value: null, child: Text('All levels')),
              for (final l in levels)
                DropdownMenuItem(value: l, child: Text(l)),
            ],
            onChanged: (v) {
              setState(() {
                _level = v;
                if (v != null) _sectionId = null;
              });
              _load();
            },
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 3),
                lastDate: DateTime(now.year + 1),
                initialDateRange: _range,
              );
              if (picked == null) return;
              setState(() => _range = picked);
              _load();
            },
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(rangeLabel),
          ),
          if (_range != null || _sectionId != null || _level != null)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _range = null;
                  _sectionId = null;
                  _level = null;
                });
                _load();
              },
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('Clear'),
            ),
          if (_loading)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent)),
          if (!_loading && kIsWeb)
            IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                color: colors.textSecondary,
                icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final colors = context.appColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      child: DropdownButtonFormField<T>(
        value: value,
        items: items,
        isExpanded: true,
        onChanged: onChanged,
        style: TextStyle(color: colors.textPrimary, fontSize: 13),
        dropdownColor: colors.surfaceAlt,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- KPIs --

  Widget _kpis(MlAnalytics d) {
    final e = d.revenue.estimate;
    final latestClosed =
        d.revenue.months.where((m) => m.collectionRate != null).toList();
    final tiles = <Widget>[
      _kpi('Students in scope', '${d.filters.studentsInScope}',
          Icons.groups_rounded, AppColors.accent),
      _kpi('Academy average', _pct(d.performance.academyAverage),
          Icons.school_rounded, AppColors.accent,
          hint: '${d.performance.totalMarks} marks'),
      _kpi('Outstanding fees', _rs(e.outstandingAmount),
          Icons.receipt_long_rounded, AppColors.warning,
          hint: '${e.outstandingChallans} challans'),
      _kpi(
          'Collection rate',
          latestClosed.isEmpty ? '—' : _pct(latestClosed.last.collectionRate),
          Icons.payments_rounded,
          AppColors.success,
          hint: latestClosed.isEmpty
              ? 'no billed months'
              : _monthLabel(latestClosed.last.period)),
      _kpi(
          'At-risk students',
          '${d.atRisk.length}',
          Icons.person_search_rounded,
          d.atRisk.isEmpty ? AppColors.success : AppColors.danger),
      _kpi(
          'ML models',
          !d.mlOk
              ? 'Offline'
              : '${_short(d.modelStatus('fee_risk'))} · ${_short(d.modelStatus('performance'))}',
          Icons.memory_rounded,
          d.feeRisk.available || d.performancePrediction.available
              ? AppColors.success
              : AppColors.warning,
          hint: 'fee risk · performance'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1100
          ? 6
          : c.maxWidth >= 720
              ? 3
              : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }

  static String _short(String status) => switch (status) {
        'PRODUCTION' => 'Live',
        'TRAINING' => 'Training',
        'READY_TO_TRAIN' => 'Ready',
        'INSUFFICIENT_DATA' => 'Needs data',
        'VALIDATED' => 'Trained',
        'TRAINING_FAILED' => 'Failed',
        _ => 'Not ready',
      };

  Widget _kpi(String label, String value, IconData icon, Color tint,
      {String? hint}) {
    final colors = context.appColors;
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: tint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
            ),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ),
          if (hint != null)
            Text(hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  // --------------------------------------------------------- performance --

  Widget _performanceTrendCard(MlAnalytics d) {
    final trend = d.performance.trend;
    final hasPredicted = trend.any((t) => t.predicted != null);
    return _section(
      title: 'Performance trend',
      subtitle: 'Monthly average of actual assessment results'
          '${hasPredicted ? ' · dashed: model holdout prediction' : ''}',
      icon: Icons.show_chart_rounded,
      child: trend.isEmpty
          ? _empty('No graded assessments in this scope yet.')
          : SizedBox(
              height: 230,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: context.appColors.border.withValues(alpha: 0.25),
                      strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                          style: TextStyle(
                              color: context.appColors.textMuted,
                              fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: (trend.length / 6).ceilToDouble().clamp(1, 99),
                      getTitlesWidget: (v, _) {
                        final i = v.round();
                        if (i < 0 || i >= trend.length || v != i) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_monthLabel(trend[i].month),
                              style: TextStyle(
                                  color: context.appColors.textMuted,
                                  fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final p = trend[s.x.toInt()];
                      final label = s.barIndex == 0 ? 'Actual' : 'Predicted';
                      return LineTooltipItem(
                        '${_monthLabel(p.month)}\n$label ${s.y.toStringAsFixed(1)}%'
                        '${s.barIndex == 0 ? '\n${p.count} marks · ${p.students} students' : ''}',
                        const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < trend.length; i++)
                        if (trend[i].average != null)
                          FlSpot(i.toDouble(), trend[i].average!),
                    ],
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
                          AppColors.accent.withValues(alpha: 0.22),
                          AppColors.accent.withValues(alpha: 0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  if (hasPredicted)
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < trend.length; i++)
                          if (trend[i].predicted != null)
                            FlSpot(i.toDouble(), trend[i].predicted!),
                      ],
                      isCurved: false,
                      color: AppColors.warning,
                      barWidth: 2,
                      dashArray: [6, 4],
                      dotData: const FlDotData(show: true),
                    ),
                ],
              )),
            ),
    );
  }

  Widget _classComparisonCard(MlAnalytics d) {
    final rows = d.performance.classes;
    return _section(
      title: 'Class comparison',
      subtitle: 'Average result per class section',
      icon: Icons.bar_chart_rounded,
      child: rows.isEmpty
          ? _empty('No class results in this scope yet.')
          : _bars(rows, AppColors.accent),
    );
  }

  Widget _subjectCard(MlAnalytics d) {
    final rows = d.performance.subjects;
    return _section(
      title: 'Subject comparison',
      subtitle: 'Average result per subject (weakest first)',
      icon: Icons.menu_book_rounded,
      child: rows.isEmpty
          ? _empty('No subject results in this scope yet.')
          : _bars(rows, AppColors.accentDark, lowIsRed: true),
    );
  }

  Widget _bars(List<LabelledAverage> rows, Color color,
      {bool lowIsRed = false}) {
    final colors = context.appColors;
    return SizedBox(
      height: (rows.length * 34.0 + 20).clamp(120, 360),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                  width: 120,
                  child: Text(r.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(children: [
                      Container(
                          height: 18,
                          color: colors.border.withValues(alpha: 0.25)),
                      FractionallySizedBox(
                        widthFactor: ((r.average ?? 0) / 100).clamp(0.0, 1.0),
                        child: Container(
                          height: 18,
                          color: lowIsRed && (r.average ?? 100) < 50
                              ? AppColors.danger
                              : color,
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text('${_pct(r.average)}  ·  ${r.count}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- revenue --

  Widget _revenueCard(MlAnalytics d) {
    final months = d.revenue.months;
    final maxBilled =
        months.fold<double>(0, (m, r) => r.billed > m ? r.billed : m);
    return _section(
      title: 'Revenue by month',
      subtitle: 'Billed vs collected from issued challans',
      icon: Icons.account_balance_wallet_rounded,
      trailing: _legend({
        'Collected': AppColors.success,
        'Pending': AppColors.warning,
        'Overdue': AppColors.danger,
      }),
      child: months.isEmpty
          ? _empty('No fee challans in this scope yet.')
          : SizedBox(
              height: 230,
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxBilled <= 0 ? 1 : maxBilled * 1.15,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, __) {
                      final m = months[group.x];
                      return BarTooltipItem(
                        '${_monthLabel(m.period)}\nBilled ${_rs(m.billed)}\n'
                        'Collected ${_rs(m.collected)}\nPending ${_rs(m.pending)}\n'
                        'Overdue ${_rs(m.overdue)}\nRate ${_pct(m.collectionRate)}',
                        const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, meta) => v == meta.max
                          ? const SizedBox.shrink()
                          : Text(_compact(v),
                              style: TextStyle(
                                  color: context.appColors.textMuted,
                                  fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= months.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_monthLabel(months[i].period),
                              style: TextStyle(
                                  color: context.appColors.textMuted,
                                  fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < months.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: months[i].billed,
                        width: months.length > 8 ? 14 : 22,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5)),
                        rodStackItems: [
                          BarChartRodStackItem(
                              0, months[i].collected, AppColors.success),
                          BarChartRodStackItem(
                              months[i].collected,
                              months[i].collected + months[i].pending,
                              AppColors.warning),
                          BarChartRodStackItem(
                              months[i].collected + months[i].pending,
                              months[i].billed,
                              AppColors.danger),
                        ],
                      ),
                    ]),
                ],
              )),
            ),
    );
  }

  static String _compact(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  Widget _revenueEstimateCard(MlAnalytics d) {
    final e = d.revenue.estimate;
    final colors = context.appColors;
    Widget stat(String label, String value, String basis, Color tint) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tint.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          color: tint == AppColors.accent
                              ? colors.accentText
                              : tint,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                Text(basis,
                    style: TextStyle(
                        color: colors.textMuted, fontSize: 11, height: 1.3)),
              ],
            ),
          ),
        );
    final stats = [
      stat(
          'Expected collection',
          _rs(e.expectedCollectionHistorical),
          e.historicalCollectionRate == null
              ? 'Needs at least one fully elapsed billing month.'
              : 'Outstanding × ${_pct(e.historicalCollectionRate)} historical rate '
                  '(${e.historicalPeriods} closed month${e.historicalPeriods == 1 ? '' : 's'}).',
          AppColors.success),
      stat(
          'Model: paid on time',
          _rs(e.expectedOnTimeModel),
          e.expectedOnTimeModel == null
              ? (d.feeRisk.available
                  ? 'No outstanding challan belongs to a scored student.'
                  : 'Appears when a validated fee-risk model is live.')
              : 'Σ amount × (1 − P(late)) over ${e.modelScoredChallans} scored challans '
                  '(${_rs(e.modelScoredAmount)}).',
          AppColors.accent),
      stat(
          'Next period billing',
          _rs(e.expectedBilledNextPeriod),
          'Average billed amount of the last three billing months.',
          AppColors.warning),
    ];
    return _section(
      title: 'Revenue estimate',
      subtitle:
          'Data-driven, each figure shows its own basis · no fixed assumptions',
      icon: Icons.query_stats_rounded,
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 620) {
          return Column(children: [
            for (var i = 0; i < stats.length; i++) ...[
              Row(children: [stats[i]]),
              if (i < stats.length - 1) const SizedBox(height: 8),
            ]
          ]);
        }
        return Row(children: [
          stats[0],
          const SizedBox(width: 10),
          stats[1],
          const SizedBox(width: 10),
          stats[2],
        ]);
      }),
    );
  }

  // ---------------------------------------------------------- predictions --

  Widget _modelMeta(String? version, Map<String, dynamic> metrics,
      DateTime? trainedAt, int? records, List<String> keys) {
    final parts = <String>[
      if (version != null && version.isNotEmpty) 'v$version',
      if (records != null) '$records training records',
      for (final k in keys)
        if (metrics[k] != null)
          '${k.toUpperCase().replaceAll('_', ' ')} ${_num(metrics[k])}',
      if (trainedAt != null)
        'trained ${DateFormat('dd MMM yyyy').format(trainedAt.toLocal())}',
    ];
    return Text(parts.join(' · '),
        style: TextStyle(color: context.appColors.textMuted, fontSize: 11));
  }

  static String _num(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    return d == null ? v.toString() : d.toStringAsFixed(d.abs() < 10 ? 3 : 1);
  }

  Widget _feeRiskCard(MlAnalytics d) {
    final f = d.feeRisk;
    final colors = context.appColors;
    if (!f.available) {
      return _section(
        title: 'Fee-delay risk (ML)',
        subtitle: 'Per-student probability of paying late',
        icon: Icons.warning_amber_rounded,
        child: _unavailable(f.status, f.reason, d),
      );
    }
    final dist = f.distribution;
    final total = dist.values.fold<int>(0, (a, b) => a + b);
    Color catColor(String c) => c == 'High Risk'
        ? AppColors.danger
        : c == 'Medium Risk'
            ? AppColors.warning
            : AppColors.success;
    return _section(
      title: 'Fee-delay risk (ML)',
      subtitle:
          '${f.scored} students scored · average risk ${_pct((f.averageProbability ?? 0) * 100)}',
      icon: Icons.warning_amber_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(children: [
                for (final c in const ['Low Risk', 'Medium Risk', 'High Risk'])
                  if ((dist[c] ?? 0) > 0)
                    Expanded(
                      flex: dist[c]!,
                      child: Container(height: 14, color: catColor(c)),
                    ),
              ]),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            for (final c in const ['Low Risk', 'Medium Risk', 'High Risk'])
              _legendDot(catColor(c), '$c ${dist[c] ?? 0}'),
          ]),
          const SizedBox(height: 10),
          _modelMeta(f.version, f.metrics, f.trainedAt, f.records,
              const ['roc_auc', 'precision', 'recall', 'f1']),
          const SizedBox(height: 10),
          Text('HIGHEST RISK',
              style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          for (final s in f.students.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: catColor(s.riskCategory),
                        shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '${s.studentName}${s.classLabel.isEmpty ? '' : ' · ${s.classLabel}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: colors.textPrimary, fontSize: 12.5)),
                ),
                Text(_rs(s.outstanding),
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
                const SizedBox(width: 10),
                Text(_pct(s.probability * 100),
                    style: TextStyle(
                        color: catColor(s.riskCategory),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          if (f.students.isEmpty) _empty('No students were scored.'),
          const SizedBox(height: 6),
          Text('Probabilities are model outputs, not calibrated guarantees.',
              style: TextStyle(color: colors.textMuted, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _performanceForecastCard(MlAnalytics d) {
    final p = d.performancePrediction;
    final colors = context.appColors;
    if (!p.available) {
      return _section(
        title: 'Performance forecast (ML)',
        subtitle: 'Predicted next-assessment marks per student and subject',
        icon: Icons.trending_up_rounded,
        child: _unavailable(p.status, p.reason, d),
      );
    }
    final lowest = p.forecast.where((f) => f.predictedNext != null).take(8);
    return _section(
      title: 'Performance forecast (ML)',
      subtitle:
          'Average predicted next mark ${_pct(p.averagePredictedNext)} across ${p.forecast.length} student-subject pairs',
      icon: Icons.trending_up_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(Icons.fact_check_rounded,
                  size: 18, color: colors.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.holdoutMae == null
                      ? 'Holdout check needs students with at least two graded assessments.'
                      : 'Holdout check on ${p.holdoutCount} latest marks: mean absolute error '
                          '${p.holdoutMae!.toStringAsFixed(1)} points. ${p.holdoutNote ?? ''}',
                  style: TextStyle(
                      color: colors.textSecondary, fontSize: 12, height: 1.3),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          _modelMeta(p.version, p.metrics, p.trainedAt, p.records,
              const ['mae', 'rmse', 'r2']),
          const SizedBox(height: 10),
          Text('LOWEST PREDICTED NEXT MARKS',
              style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          for (final f in lowest)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text('${f.studentName} · ${f.subject}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: colors.textPrimary, fontSize: 12.5)),
                ),
                Text('last ${_pct(f.latestActual)}',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
                const SizedBox(width: 10),
                Text(_pct(f.predictedNext),
                    style: TextStyle(
                        color: (f.predictedNext ?? 100) < d.atRiskThreshold
                            ? AppColors.danger
                            : colors.accentText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          if (lowest.isEmpty) _empty('No student-subject pairs to forecast.'),
        ],
      ),
    );
  }

  Widget _unavailable(String status, String? reason, MlAnalytics d) {
    final colors = context.appColors;
    final label = switch (status) {
      'TRAINING' => 'Training in progress',
      'READY_TO_TRAIN' => 'Enough data – train the model from AI Insights',
      'INSUFFICIENT_DATA' => 'Not enough labelled records to train yet',
      'VALIDATED' => 'Trained but not promoted to production',
      'TRAINING_FAILED' => 'Last training run failed',
      _ => d.mlOk ? 'No validated production model' : 'ML service offline',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded,
            color: AppColors.warning, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              if (reason != null && reason.isNotEmpty)
                Text(reason,
                    style: TextStyle(color: colors.textMuted, fontSize: 11.5)),
              Text('Nothing is estimated here until a real model is validated.',
                  style: TextStyle(color: colors.textMuted, fontSize: 11.5)),
            ],
          ),
        ),
      ]),
    );
  }

  // --------------------------------------------------------------- at-risk --

  Widget _atRiskCard(MlAnalytics d) {
    final colors = context.appColors;
    return _section(
      title: 'Students needing attention',
      subtitle: d.atRiskRule,
      icon: Icons.person_search_rounded,
      child: d.atRisk.isEmpty
          ? _empty(
              'No student is below ${d.atRiskThreshold}% or flagged by a model in this scope.')
          : Column(children: [
              for (final s in d.atRisk.take(25))
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            AppColors.danger.withValues(alpha: 0.15),
                        child: Text('${s.reasons.length}',
                            style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${s.studentName}${s.classLabel.isEmpty ? '' : ' · ${s.classLabel}'}',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            for (final r in s.reasons)
                              Text('• $r',
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (d.atRisk.length > 25)
                Text('…and ${d.atRisk.length - 25} more',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
            ]),
    );
  }

  // ------------------------------------------------------------ primitives --

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.5)),
        ),
        child: child,
      );

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    final colors = context.appColors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: colors.accentText),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  Text(subtitle,
                      style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11.5,
                          height: 1.3)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _banner(String text, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 12,
                    height: 1.35)),
          ),
        ]),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.appColors.textMuted, fontSize: 12.5)),
        ),
      );

  Widget _legend(Map<String, Color> items) => Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final e in items.entries) _legendDot(e.value, e.key),
        ],
      );

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 11)),
        ],
      );
}
