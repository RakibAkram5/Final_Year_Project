import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/fee_challan_model.dart';
import '../../../data/repositories/fee_challan_repository.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

final _currency =
    NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ', decimalDigits: 0);

/// Academy-wide view of every student with an unpaid (pending/overdue) fee
/// challan, grouped by class — the class-scoped equivalent already exists
/// per-class in ClassFeeStatusScreen, but there was no single place to see
/// every defaulter across the whole academy at once.
class UnpaidStudentsScreen extends StatefulWidget {
  const UnpaidStudentsScreen({super.key});

  @override
  State<UnpaidStudentsScreen> createState() => _UnpaidStudentsScreenState();
}

class _UnpaidStudentsScreenState extends State<UnpaidStudentsScreen> {
  final _repo = FeeChallanRepository();
  bool _loading = true;
  String? _error;
  List<FeeChallanModel> _unpaid = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid;
    if (academyId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _repo.getAll(academyId);
      final unpaid = all.where((c) => !c.isPaid).toList()
        ..sort((a, b) => a.classLabel.compareTo(b.classLabel));
      if (mounted) setState(() => _unpaid = unpaid);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markPaid(FeeChallanModel c) async {
    try {
      await _repo.updateStatus(c.id, 'paid');
      if (mounted) setState(() => _unpaid.removeWhere((x) => x.id == c.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.danger));
      }
    }
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
        title: const Text('Unpaid Students',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
      title: 'Unpaid Students',
      titleIcon: Icons.money_off_rounded,
      navSections: navSections,
      activeNavId: 'unpaid_students',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(),
    );
  }

  Widget _body() {
    final Map<String, List<FeeChallanModel>> byClass = {};
    for (final c in _unpaid) {
      byClass.putIfAbsent(c.classLabel, () => []).add(c);
    }

    return _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.accent))
        : _error != null
            ? Center(
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger)))
            : RefreshIndicator(
                color: AppColors.accent,
                onRefresh: _load,
                child: _unpaid.isEmpty
                    ? _emptyState()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: byClass.entries
                            .map((e) => _classGroup(e.key, e.value))
                            .toList(),
                      ),
              );
  }

  Widget _emptyState() {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 100),
          child: Column(
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 56, color: AppColors.success),
              const SizedBox(height: 12),
              Text('No unpaid students right now',
                  style: TextStyle(color: context.appColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _classGroup(String classLabel, List<FeeChallanModel> challans) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(classLabel,
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              subtitle: Text(
                  '${challans.length} unpaid student${challans.length == 1 ? '' : 's'}',
                  style:
                      const TextStyle(color: AppColors.danger, fontSize: 12)),
              children: challans.map(_challanTile).toList(),
            ),
          )),
    );
  }

  Widget _challanTile(FeeChallanModel c) {
    return ListTile(
      leading: Icon(
        c.isOverdue ? Icons.warning_amber_rounded : Icons.pending_rounded,
        color: c.isOverdue ? AppColors.danger : AppColors.warning,
      ),
      title: Text(c.studentName,
          style: TextStyle(
              color: context.appColors.textPrimary,
              fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${c.rollNumber.isNotEmpty ? 'Roll: ${c.rollNumber} • ' : ''}Due ${DateFormat('d MMM yyyy').format(c.dueDate)}',
          style: TextStyle(color: context.appColors.textMuted, fontSize: 12)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_currency.format(c.totalAmount),
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _markPaid(c),
            child: const Text('Mark Paid',
                style: TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
