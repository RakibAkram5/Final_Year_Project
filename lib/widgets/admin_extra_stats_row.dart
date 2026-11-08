import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../data/models/announcement.dart';
import '../data/models/fee_challan_model.dart';
import '../data/remote/announcement_service.dart';
import '../data/repositories/attendance_repository.dart';
import '../data/repositories/fee_challan_repository.dart';
import 'dashboard_stat_card.dart';

final _currency =
    NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ', decimalDigits: 0);

/// Second stat row for the Admin dashboard — Fee Summary (pending, academy
/// wide), Attendance Summary (today's marked-present %), and total
/// Announcements — alongside the existing Teachers/Students/Parents counts.
class AdminExtraStatsRow extends StatelessWidget {
  final String academyId;
  final VoidCallback? onFeeTap;
  final VoidCallback? onAnnouncementsTap;

  const AdminExtraStatsRow({
    super.key,
    required this.academyId,
    this.onFeeTap,
    this.onAnnouncementsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<List<FeeChallanModel>>(
            future: FeeChallanRepository().getAll(academyId),
            builder: (context, snap) {
              final pending = (snap.data ?? const [])
                  .where((c) => !c.isPaid)
                  .fold<double>(0.0, (sum, c) => sum + c.totalAmount);
              return DashboardStatCard(
                  label: 'Fee Pending',
                  value: snap.hasData ? _currency.format(pending) : '--',
                  icon: Icons.receipt_long_rounded,
                  color: AppColors.warning,
                  onTap: onFeeTap);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FutureBuilder(
            future: AttendanceRepository().getAllForAcademy(academyId,
                from: DateTime.now(), to: DateTime.now()),
            builder: (context, snap) {
              final today = DateTime.now();
              final records = (snap.data ?? const []).where((r) =>
                  r.logDate.year == today.year &&
                  r.logDate.month == today.month &&
                  r.logDate.day == today.day);
              final total = records.length;
              final present =
                  records.where((r) => r.isPresent || r.isLate).length;
              final pct = total == 0 ? null : (present / total) * 100;
              return DashboardStatCard(
                  label: "Today's Attendance",
                  value: pct == null ? '--' : '${pct.round()}%',
                  icon: Icons.fact_check_rounded,
                  color: AppColors.success);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder<List<Announcement>>(
            stream: AnnouncementService().watchAll(academyId),
            builder: (context, snap) => DashboardStatCard(
                label: 'Announcements',
                value: snap.hasData ? '${snap.data!.length}' : '--',
                icon: Icons.campaign_rounded,
                color: AppColors.accent,
                onTap: onAnnouncementsTap),
          ),
        ),
      ],
    );
  }
}
