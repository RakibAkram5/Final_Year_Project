import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/attendance_provider.dart';
import '../../../data/models/attendance_record.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class ChildAlertsScreen extends StatelessWidget {
  final String childName;
  final String childUid;

  const ChildAlertsScreen(
      {super.key, required this.childName, required this.childUid});

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
        title: Text('$childName\'s Alerts',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(context),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildParentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: '$childName\'s Alerts',
      titleIcon: Icons.notifications_active_rounded,
      navSections: navSections,
      activeNavId: 'dashboard',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final academyId = Provider.of<AuthProvider>(context, listen: false)
            .currentUser
            ?.academyId ??
        '';

    return academyId.isEmpty
        ? const Center(child: Text("Session error"))
        : StreamBuilder<List<AttendanceRecord>>(
            stream: context
                .read<AttendanceProvider>()
                .watchStudentAttendance(childUid, academyId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent));
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: AppColors.danger),
                        const SizedBox(height: 12),
                        Text(
                            "Could not load attendance alerts. "
                            "Check your connection.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: context.appColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }

              final absences = (snapshot.data ?? [])
                  .where((r) => r.status == 'absent')
                  .toList();

              if (absences.isEmpty) {
                return _buildEmptyState(context);
              }

              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: absences.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _alertTile(context, absences[i]),
              );
            },
          );
  }

  Widget _alertTile(BuildContext context, AttendanceRecord r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Absence Alert',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text('$childName was marked Absent.',
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.bold)),
                Text(DateFormat('EEEE, MMM d, yyyy').format(r.logDate),
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 64,
              color: context.appColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No new alerts',
              style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontWeight: FontWeight.bold)),
          Text('Your child has been regular!',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
