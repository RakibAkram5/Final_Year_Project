import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../data/models/fee_challan_model.dart';
import '../../../data/repositories/fee_challan_repository.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class StudentFeeScreen extends StatefulWidget {
  final String studentUid;
  const StudentFeeScreen({super.key, required this.studentUid});

  @override
  State<StudentFeeScreen> createState() => _StudentFeeScreenState();
}

class _StudentFeeScreenState extends State<StudentFeeScreen> {
  final _repo = FeeChallanRepository();
  late Future<List<FeeChallanModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadChallans();
  }

  Future<List<FeeChallanModel>> _loadChallans() {
    final user = context.read<AuthProvider>().currentUser;
    return _repo.getForStudent(widget.studentUid, user?.academyId ?? '');
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
        title: const Text('Fee Status',
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
    final navSections = buildStudentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Fee Status',
      titleIcon: Icons.receipt_long_rounded,
      navSections: navSections,
      activeNavId: 'fee_status',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(),
    );
  }

  Widget _body() {
    return FutureBuilder<List<FeeChallanModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }

        if (snapshot.hasError) {
          return _buildErrorState('${snapshot.error}');
        }

        final challans = snapshot.data ?? [];

        if (challans.isEmpty) {
          return _buildEmptyState();
        }

        return Column(
          children: [
            _buildSummaryHeader(challans),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: challans.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _feeTile(challans[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryHeader(List<FeeChallanModel> challans) {
    final pending = challans
        .where((i) => !i.isPaid)
        .fold(0.0, (sum, i) => sum + i.totalAmount);

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("TOTAL PAYABLE",
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              Text("Rs. ${pending.toStringAsFixed(0)}",
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontSize: 28,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: context.appColors.accentText, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _feeTile(FeeChallanModel c) {
    final bool isOverdue = c.isOverdue && !c.isPaid;
    final Color statusColor = c.isPaid
        ? AppColors.success
        : (isOverdue ? AppColors.danger : AppColors.warning);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.challanNumber,
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  c.isPaid
                      ? "Paid"
                      : "Due Date: ${DateFormat('MMM d, yyyy').format(c.dueDate)}",
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "Rs. ${c.totalAmount.toStringAsFixed(0)}",
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  c.status.toUpperCase(),
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_outlined,
              size: 64, color: context.appColors.textMuted),
          const SizedBox(height: 16),
          Text("No fee records found.",
              style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            Text("Could not load your fee records.",
                style: TextStyle(color: context.appColors.textSecondary)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => setState(() => _future = _loadChallans()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
