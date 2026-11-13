import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/models/fee_challan_model.dart';
import '../../../data/repositories/fee_challan_repository.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/challan_actions.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class ClassFeeStatusScreen extends StatefulWidget {
  final ClassEntity classEntity;
  const ClassFeeStatusScreen({super.key, required this.classEntity});

  @override
  State<ClassFeeStatusScreen> createState() => _ClassFeeStatusScreenState();
}

class _ClassFeeStatusScreenState extends State<ClassFeeStatusScreen> {
  final _repo = FeeChallanRepository();
  String _selectedMonth = DateFormat('MMMM').format(DateTime.now());

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

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
        title: Text('${widget.classEntity.className} - Fee Status',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
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
      title: '${widget.classEntity.className} - Fee Status',
      titleIcon: Icons.receipt_long_rounded,
      navSections: navSections,
      activeNavId: 'class_management',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(),
    );
  }

  Widget _body() {
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
            '';
    final studentIds = widget.classEntity.studentIds;

    return Column(
      children: [
        _buildMonthFilter(),
        Expanded(
          child: studentIds.isEmpty
              ? _buildEmptyState("No students enrolled in this class.")
              : FutureBuilder<Map<String, FeeChallanModel?>>(
                  future: _repo.getLatestForStudents(studentIds, academyId,
                      month: _selectedMonth),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent));
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text(
                              'Error loading fee status: ${snapshot.error}',
                              style: const TextStyle(color: AppColors.danger)));
                    }
                    final challansByStudent = snapshot.data ?? {};
                    return ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: studentIds.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final sid = studentIds[index];
                        final sname =
                            widget.classEntity.studentNames[sid] ?? 'Student';
                        return _studentFeeTile(sname, challansByStudent[sid]);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMonthFilter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("FILTER BY BILLING MONTH",
              style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.appColors.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: context.appColors.border.withValues(alpha: 0.5)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMonth,
                isExpanded: true,
                dropdownColor: context.appColors.surfaceAlt,
                items: _months
                    .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m,
                            style: TextStyle(
                                color: context.appColors.textPrimary))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMonth = v!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentFeeTile(String sname, FeeChallanModel? challan) {
    Color statusColor = context.appColors.textMuted;
    String statusText = "No Challan";

    if (challan != null) {
      if (challan.isPaid) {
        statusColor = AppColors.success;
        statusText = "PAID";
      } else if (challan.isOverdue) {
        statusColor = AppColors.danger;
        statusText = "OVERDUE";
      } else {
        statusColor = AppColors.warning;
        statusText = "PENDING";
      }
    }

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
          CircleAvatar(
            backgroundColor: AppColors.accent.withValues(alpha: 0.1),
            child: Text(sname.isNotEmpty ? sname[0].toUpperCase() : '?',
                style: TextStyle(
                    color: context.appColors.accentText,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sname,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.bold)),
                if (challan != null)
                  Text("Amount: Rs. ${challan.totalAmount.toStringAsFixed(0)}",
                      style: TextStyle(
                          color: context.appColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(statusText,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
          if (challan != null)
            IconButton(
              icon: Icon(Icons.picture_as_pdf_outlined,
                  color: context.appColors.textSecondary, size: 20),
              onPressed: () => ChallanActions.showSheet(context, challan),
              tooltip: "Download / print / share challan",
            ),
          if (challan != null && !challan.isPaid)
            IconButton(
              icon: Icon(Icons.check_circle_outline,
                  color: context.appColors.accentText, size: 20),
              onPressed: () => _markPaid(challan),
              tooltip: "Mark as Paid",
            ),
        ],
      ),
    );
  }

  Future<void> _markPaid(FeeChallanModel challan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: const Text("Confirm Payment"),
        content: Text(
            "Mark Rs. ${challan.totalAmount.toStringAsFixed(0)} as paid for ${challan.studentName}?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Confirm",
                  style: TextStyle(color: AppColors.success))),
        ],
      ),
    );

    if (ok == true) {
      await _repo.updateStatus(challan.id, 'paid');
      setState(() {}); // Refresh UI
    }
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: context.appColors.textMuted),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }
}
