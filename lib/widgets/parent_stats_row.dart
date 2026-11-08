import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../data/models/app_user.dart';
import '../data/models/test_mark_model.dart';
import '../data/remote/announcement_service.dart';
import '../data/repositories/attendance_repository.dart';
import '../data/repositories/fee_challan_repository.dart';
import '../logic/quiz_provider.dart';
import 'dashboard_stat_card.dart';

final _currency =
    NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ', decimalDigits: 0);

/// "At a glance" row for the Parent dashboard — Child Attendance (averaged
/// across every linked child), Fee Status (total pending across every
/// linked child), Latest Announcement, and Child Performance (first
/// child's average test score, same "first child" convention the Academy
/// Support tile already uses elsewhere on this dashboard).
class ParentStatsRow extends StatefulWidget {
  final List<AppUser> children;
  final String academyId;

  const ParentStatsRow(
      {super.key, required this.children, required this.academyId});

  @override
  State<ParentStatsRow> createState() => _ParentStatsRowState();
}

class _ParentStatsRowState extends State<ParentStatsRow> {
  late Future<double?> _attendanceFuture;
  late Future<double> _pendingFeeFuture;

  @override
  void initState() {
    super.initState();
    _attendanceFuture = _computeAttendance();
    _pendingFeeFuture = _computePendingFee();
  }

  @override
  void didUpdateWidget(covariant ParentStatsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      _attendanceFuture = _computeAttendance();
      _pendingFeeFuture = _computePendingFee();
    }
  }

  Future<double?> _computeAttendance() async {
    if (widget.children.isEmpty) return null;
    final childUids = widget.children.map((c) => c.uid).toSet();
    final all = await AttendanceRepository().getAllForAcademy(widget.academyId);
    final records = all.where((r) => childUids.contains(r.studentId)).toList();
    if (records.isEmpty) return null;
    final present = records.where((r) => r.isPresent || r.isLate).length;
    return (present / records.length) * 100;
  }

  Future<double> _computePendingFee() async {
    if (widget.children.isEmpty) return 0;
    // Parents may only read their own children's challans
    // (/fees/challans is admin-only).
    final repo = FeeChallanRepository();
    var total = 0.0;
    for (final child in widget.children) {
      final challans = await repo.getForStudent(child.uid, widget.academyId);
      total += challans
          .where((c) => !c.isPaid)
          .fold<double>(0.0, (sum, c) => sum + c.totalAmount);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final firstChild = widget.children.isEmpty ? null : widget.children.first;

    return Row(
      children: [
        Expanded(
          child: FutureBuilder<double?>(
            future: _attendanceFuture,
            builder: (context, snap) => DashboardStatCard(
                label: 'Attendance',
                value: snap.data == null ? '--' : '${snap.data!.round()}%',
                icon: Icons.fact_check_rounded,
                color: AppColors.success),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FutureBuilder<double>(
            future: _pendingFeeFuture,
            builder: (context, snap) => DashboardStatCard(
                label: 'Fee Pending',
                value: snap.hasData ? _currency.format(snap.data) : '--',
                icon: Icons.receipt_long_rounded,
                color: AppColors.warning),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder(
            stream:
                AnnouncementService().watchForRole('parent', widget.academyId),
            builder: (context, snap) {
              final list = (snap.data as List?) ?? const [];
              return DashboardStatCard(
                  label: 'Announcements',
                  value: '${list.length}',
                  icon: Icons.campaign_rounded,
                  color: AppColors.accent);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: firstChild == null
              ? const DashboardStatCard(
                  label: 'Performance',
                  value: '--',
                  icon: Icons.insights_rounded,
                  color: AppColors.accentDark)
              : StreamBuilder<List<TestMarkModel>>(
                  stream: context
                      .read<QuizProvider>()
                      .watchStudentResults(firstChild.uid, widget.academyId),
                  builder: (context, snap) {
                    final marks = snap.data ?? const [];
                    final avg = marks.isEmpty
                        ? null
                        : marks
                                .map((m) => m.percentage)
                                .reduce((a, b) => a + b) /
                            marks.length;
                    return DashboardStatCard(
                        label: 'Performance',
                        value: avg == null ? '--' : '${avg.round()}%',
                        icon: Icons.insights_rounded,
                        color: AppColors.accentDark);
                  },
                ),
        ),
      ],
    );
  }
}
