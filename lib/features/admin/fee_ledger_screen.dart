import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/fee_challan_model.dart';
import '../../data/repositories/fee_challan_repository.dart';
import '../../logic/auth_provider.dart';
import '../../logic/class_section_provider.dart';
import '../../logic/fee_analytics_service.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_cards.dart';
import '../../widgets/web/web_data_table.dart';
import '../../widgets/web/web_empty_state.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

final _currency =
    NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ', decimalDigits: 0);

/// Read-only fee analytics for the academy — class+section wise totals,
/// paid/pending/overdue, and collection %, sourced from the same
/// [FeeChallanRepository] the AI prediction screen already reads. There is
/// no manual invoice entry here anymore; challans are generated in bulk
/// (Bulk Fee Challans) and individual ones are managed on the Unpaid
/// Students screen — this screen is purely a summary view.
class FeeLedgerScreen extends StatefulWidget {
  const FeeLedgerScreen({super.key});

  @override
  State<FeeLedgerScreen> createState() => _FeeLedgerScreenState();
}

class _FeeLedgerScreenState extends State<FeeLedgerScreen> {
  final _repo = FeeChallanRepository();
  bool _loading = true;
  String? _error;
  List<FeeChallanModel> _challans = [];
  String _selectedMonth = 'All Months';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user != null) {
        context.read<ClassSectionProvider>().listenAll(user.uid);
      }
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
            '';
    try {
      final all = await _repo.getAll(academyId);
      if (!mounted) return;
      setState(() {
        _challans = all;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load fee records: $e';
        _loading = false;
      });
    }
  }

  List<FeeChallanModel> get _filteredChallans {
    if (_selectedMonth == 'All Months') return _challans;
    return _challans
        .where((c) =>
            DateFormat('MMMM yyyy').format(c.billingMonth) == _selectedMonth)
        .toList();
  }

  List<String> get _availableMonths {
    // Sort chronologically (newest first), then format for display.
    final months = _challans.map((c) => c.billingMonth).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      'All Months',
      ...months.map((m) => DateFormat('MMMM yyyy').format(m)),
    ];
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Fee Ledger',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: _load,
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));

    return WebAppShell(
      title: 'Fee Ledger',
      titleIcon: Icons.receipt_long_rounded,
      navSections: navSections,
      activeNavId: 'fee_ledger',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fee Ledger',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: context.appColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                        'Class + section wise fee analytics across the academy.',
                        style:
                            TextStyle(color: context.appColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _monthDropdown(context),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _monthDropdown(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.appColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedMonth,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: context.appColors.textMuted),
          items: _availableMonths
              .map((m) => DropdownMenuItem(
                  value: m,
                  child: Text(m,
                      style: TextStyle(color: context.appColors.textPrimary))))
              .toList(),
          onChanged: (v) => setState(() => _selectedMonth = v!),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final sections = context.watch<ClassSectionProvider>().sections;
    final analytics =
        FeeAnalyticsService.computeClassAnalytics(_filteredChallans, sections);

    final totalPaid = analytics.fold(0.0, (s, a) => s + a.paidAmount);
    final totalPending = analytics.fold(0.0, (s, a) => s + a.pendingAmount);
    final totalOverdue = analytics.fold(0.0, (s, a) => s + a.overdueAmount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        if (!kIsWeb || WebBreakpoints.isCompact(context)) ...[
          _mobileMonthFilter(),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(builder: (context, constraints) {
          final stats = [
            WebStatCard(
                label: 'Collected',
                value: _currency.format(totalPaid),
                icon: Icons.check_circle_rounded,
                accent: AppColors.success),
            WebStatCard(
                label: 'Pending',
                value: _currency.format(totalPending),
                icon: Icons.hourglass_bottom_rounded,
                accent: AppColors.warning),
            WebStatCard(
                label: 'Overdue',
                value: _currency.format(totalOverdue),
                icon: Icons.error_outline_rounded,
                accent: AppColors.danger),
          ];
          final narrow = constraints.maxWidth < 640;
          return narrow
              ? Column(children: [
                  for (final s in stats) ...[s, const SizedBox(height: 16)],
                ])
              : Row(children: [
                  for (int i = 0; i < stats.length; i++) ...[
                    Expanded(child: stats[i]),
                    if (i != stats.length - 1) const SizedBox(width: 16),
                  ],
                ]);
        }),
        const SizedBox(height: 24),
        const Text('BY CLASS & SECTION',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        if (analytics.isEmpty)
          const WebEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No fee records yet',
            message:
                'Generate bulk fee challans for a class to see analytics here.',
          )
        else if (kIsWeb && !WebBreakpoints.isCompact(context))
          _webTable(analytics)
        else
          ...analytics.map(_classCard),
      ],
    );
  }

  Widget _mobileMonthFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedMonth,
          isExpanded: true,
          dropdownColor: AppColors.surfaceAlt,
          items: _availableMonths
              .map((m) => DropdownMenuItem(
                  value: m,
                  child: Text(m,
                      style: const TextStyle(color: AppColors.textPrimary))))
              .toList(),
          onChanged: (v) => setState(() => _selectedMonth = v!),
        ),
      ),
    );
  }

  Widget _webTable(List<ClassFeeAnalytics> analytics) {
    return WebDataTable<ClassFeeAnalytics>(
      items: analytics,
      columns: [
        WebTableColumn<ClassFeeAnalytics>(
          label: 'CLASS & SECTION',
          flex: 2,
          sortValue: (a) => a.classLabel,
          cellBuilder: (context, a) => Text(a.classLabel,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.appColors.textPrimary)),
        ),
        WebTableColumn<ClassFeeAnalytics>(
          label: 'STUDENTS',
          sortValue: (a) => a.totalStudents,
          cellBuilder: (context, a) => Text('${a.totalStudents}',
              style: TextStyle(color: context.appColors.textSecondary)),
        ),
        WebTableColumn<ClassFeeAnalytics>(
          label: 'PAID',
          sortValue: (a) => a.paidAmount,
          cellBuilder: (context, a) => Text(
              '${a.paidCount} · ${_currency.format(a.paidAmount)}',
              style: const TextStyle(
                  color: AppColors.success, fontWeight: FontWeight.w600)),
        ),
        WebTableColumn<ClassFeeAnalytics>(
          label: 'PENDING',
          sortValue: (a) => a.pendingAmount,
          cellBuilder: (context, a) => Text(
              '${a.pendingCount} · ${_currency.format(a.pendingAmount)}',
              style: const TextStyle(color: AppColors.warning)),
        ),
        WebTableColumn<ClassFeeAnalytics>(
          label: 'OVERDUE',
          sortValue: (a) => a.overdueAmount,
          cellBuilder: (context, a) => Text(
              '${a.overdueCount} · ${_currency.format(a.overdueAmount)}',
              style: const TextStyle(color: AppColors.danger)),
        ),
        WebTableColumn<ClassFeeAnalytics>(
          label: 'COLLECTION %',
          sortValue: (a) => a.collectionPercent,
          cellBuilder: (context, a) =>
              Text('${a.collectionPercent.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: a.collectionPercent >= 75
                          ? AppColors.success
                          : a.collectionPercent >= 40
                              ? AppColors.warning
                              : AppColors.danger)),
        ),
      ],
    );
  }

  Widget _classCard(ClassFeeAnalytics a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(a.classLabel,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                Text('${a.collectionPercent.toStringAsFixed(0)}% collected',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: a.collectionPercent >= 75
                            ? AppColors.success
                            : a.collectionPercent >= 40
                                ? AppColors.warning
                                : AppColors.danger)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${a.totalStudents} students',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 10),
            Row(
              children: [
                _pill('Paid', a.paidCount, AppColors.success),
                const SizedBox(width: 8),
                _pill('Pending', a.pendingCount, AppColors.warning),
                const SizedBox(width: 8),
                _pill('Overdue', a.overdueCount, AppColors.danger),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
