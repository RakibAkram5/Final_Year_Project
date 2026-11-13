import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../shared/assignments_screen.dart';
import '../../shared/documents_screen.dart';
import '../../../data/remote/file_service.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/app_user.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../student/screens/student_attendance_screen.dart';
import '../../quiz/screens/online_tests_screen.dart';
import '../../quiz/screens/student_test_report_screen.dart';
import '../../student/screens/student_progress_chart_screen.dart';

import 'student_challan_screen.dart';
import 'child_alerts_screen.dart'; // NEW

class ChildOverviewScreen extends StatelessWidget {
  final AppUser child;
  const ChildOverviewScreen({super.key, required this.child});

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
        title: Text(child.fullName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
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
    final navSections = buildParentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: child.fullName,
      titleIcon: Icons.person_rounded,
      navSections: navSections,
      activeNavId: 'dashboard',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _childProfileHeader(context),
        const SizedBox(height: 24),
        Text('LEARNING PROGRESS',
            style: TextStyle(
                color: context.appColors.accentText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Attendance History',
          'View daily presence records',
          Icons.fact_check_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      StudentAttendanceScreen(studentUid: child.uid))),
        ),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Assignments',
          'Homework, submissions and grades',
          Icons.assignment_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AssignmentsScreen(
                      childId: child.uid, childName: child.fullName))),
        ),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Documents',
          'Admission papers and certificates',
          Icons.folder_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DocumentsScreen(
                      title: '${child.fullName} · Documents',
                      category: FileCategory.studentDocument,
                      ownerId: child.uid))),
        ),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Important Alerts',
          'Absence and performance notifications',
          Icons.notifications_active_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ChildAlertsScreen(
                      childName: child.fullName, childUid: child.uid))),
        ),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Online Tests',
          'Results of tests attempted in the portal',
          Icons.quiz_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => OnlineTestsScreen(
                      studentUid: child.uid, studentName: child.fullName))),
        ),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Test Reports',
          'Check marks and subject grades',
          Icons.analytics_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StudentTestReportScreen(
                      studentUid: child.uid, studentName: child.fullName))),
        ),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Performance Analytics',
          'Growth charts and trends',
          Icons.insights_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      StudentProgressChartScreen(studentUid: child.uid))),
        ),
        const SizedBox(height: 24),
        Text('FINANCE',
            style: TextStyle(
                color: context.appColors.accentText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        _actionTile(
          context,
          'Fee Statements',
          'Payment history and pending dues',
          Icons.receipt_long_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StudentChallanScreen(studentUid: child.uid))),
        ),
      ],
    );
  }

  Widget _childProfileHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            child: Text(
                child.fullName.isNotEmpty
                    ? child.fullName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: context.appColors.accentText,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(child.fullName,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                Text(child.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.appColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, String title, String subtitle,
      IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.appColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.appColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, color: context.appColors.accentText, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        style: TextStyle(
                            color: context.appColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.appColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
