import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/class_report_model.dart';
import '../../../data/models/class_section.dart';
import '../../../data/repositories/class_report_repository.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_section_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_empty_state.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

final _currency =
    NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ', decimalDigits: 0);

/// Point-in-time class+section snapshots (attendance + fee standing),
/// generated on demand and kept until an admin deletes them.
class ClassReportsScreen extends StatefulWidget {
  const ClassReportsScreen({super.key});

  @override
  State<ClassReportsScreen> createState() => _ClassReportsScreenState();
}

class _ClassReportsScreenState extends State<ClassReportsScreen> {
  final _reportRepo = ClassReportRepository();
  // Created once so rebuilds don't refetch; refreshed via DataChanges.
  late final Stream<List<ClassReportModel>> _reportsStream =
      _reportRepo.watchAll(_academyId);
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user != null) {
        context.read<ClassSectionProvider>().listenAll(user.uid);
      }
    });
  }

  String get _academyId =>
      Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ?? '';

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
        title: const Text('Class Reports',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textOnAccent,
        icon: _generating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textOnAccent))
            : const Icon(Icons.add_rounded),
        label: const Text('Generate Report'),
        onPressed: _generating ? null : _pickClassAndGenerate,
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
      title: 'Class Reports',
      titleIcon: Icons.summarize_rounded,
      navSections: navSections,
      activeNavId: 'class_reports',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Class Reports',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                onPressed: _generating ? null : _pickClassAndGenerate,
                icon: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.textOnAccent))
                    : const Icon(Icons.add_rounded, size: 18),
                label: const Text('Generate Report'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textOnAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    return StreamBuilder<List<ClassReportModel>>(
      stream: _reportsStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        final reports = snap.data ?? const [];
        if (reports.isEmpty) {
          return const WebEmptyState(
            icon: Icons.summarize_outlined,
            title: 'No reports yet',
            message:
                'Generate a report for a class+section to snapshot its attendance and fee standing.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _reportCard(reports[i]),
        );
      },
    );
  }

  Widget _reportCard(ClassReportModel r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.classLabel,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => _confirmDelete(r),
              ),
            ],
          ),
          Text(DateFormat('d MMM yyyy, h:mm a').format(r.generatedAt),
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 11)),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Students', '${r.totalStudents}', AppColors.accent),
              _stat('Present', '${r.present}', AppColors.success),
              _stat('Absent', '${r.absent}', AppColors.danger),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                    'Fee Paid: ${r.feePaid} (${_currency.format(r.feePaidAmount)})',
                    style: const TextStyle(
                        color: AppColors.success, fontSize: 12)),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                    'Fee Pending: ${r.feePending} (${_currency.format(r.feePendingAmount)})',
                    style: const TextStyle(
                        color: AppColors.warning, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ClassReportModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text('Remove the ${r.classLabel} report from '
            '${DateFormat('d MMM yyyy').format(r.generatedAt)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true) {
      await _reportRepo.delete(r.id);
    }
  }

  Future<void> _pickClassAndGenerate() async {
    final sections = context.read<ClassSectionProvider>().sections;
    if (sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a class section first.')));
      return;
    }
    final section = await showDialog<ClassSectionEntity>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick a class & section'),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sections.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(sections[i].displayLabel),
              subtitle: Text('${sections[i].enrollmentCount} students'),
              onTap: () => Navigator.pop(ctx, sections[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (section == null) return;
    await _generateReport(section);
  }

  Future<void> _generateReport(ClassSectionEntity section) async {
    setState(() => _generating = true);
    try {
      // Counts are computed server-side from stored attendance and fee
      // records for the caller's local "today".
      await _reportRepo.generate(sectionId: section.id, asOf: DateTime.now());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Report generated for ${section.displayLabel}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}
