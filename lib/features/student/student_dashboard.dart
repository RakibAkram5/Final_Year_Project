import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../shared/assignments_screen.dart';
import '../shared/documents_screen.dart';
import '../shared/academy_location.dart';
import '../../data/remote/file_service.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../logic/auth_provider.dart';
import '../../logic/session_provider.dart';
import '../../logic/attendance_provider.dart';
import '../../logic/class_provider.dart';
import '../../logic/quiz_provider.dart';
import '../../data/models/class_entity.dart';
import '../../data/models/test_mark_model.dart';
import '../../data/remote/auth_service.dart';
import '../../data/remote/notification_service.dart';
import 'screens/my_classroom_hub.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/dashboard_app_bar_actions.dart';
import '../../widgets/latest_announcement_card.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';
import '../shared/notifications_screen.dart';
import '../../widgets/gradient_background.dart';
import '../../core/theme/theme_extensions.dart';
import '../quiz/screens/student_test_report_screen.dart';
import '../shared/view_announcements_screen.dart';
import 'screens/student_attendance_screen.dart';
import 'screens/student_fee_screen.dart';
import 'screens/ai_summarizer_screen.dart';
import 'screens/student_progress_chart_screen.dart';
import 'screens/my_timetable_screen.dart';
import '../../widgets/academy_relink_dialog.dart';
import '../../widgets/security_question_dialog.dart';

const _kQuotes = [
  "Small steps every day lead to big results.",
  "Discipline is choosing what you want most over what you want now.",
  "Every expert was once a beginner.",
  "Your only limit is your mind.",
  "Success is the sum of small efforts, repeated daily.",
  "Learning never exhausts the mind.",
  "Push yourself, because no one else is going to do it for you.",
];

class _ModuleItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _ModuleItem(this.title, this.subtitle, this.icon, this.onTap);
}

class StudentDashboard extends StatelessWidget {
  const StudentDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (r) => false);
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _quoteOfTheDay() => _kQuotes[DateTime.now().day % _kQuotes.length];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final uid = user?.uid ?? '';
    final academyId = user?.academyId ?? '';

    // Built once and reused by whichever chrome (mobile Scaffold or web
    // shell) ends up being returned below — the nested StreamBuilders only
    // actually subscribe once Flutter mounts the branch that gets returned.
    final content = _dashboardContent(context, user, uid, academyId);

    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context, user, content);
    }
    return _buildMobileLayout(context, user, content);
  }

  Widget _buildMobileLayout(
      BuildContext context, AppUser? user, Widget content) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.school_rounded,
                color: context.appColors.accentText, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Student Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        actions: dashboardAppBarActions(context,
            notificationBell: _notificationBell(context, user),
            onSecurity: () => _showSecuritySettings(context),
            onLogout: () => _logout(context)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: content,
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context, AppUser? user, Widget content) {
    final navSections = buildStudentNavSections(context, onDashboard: () {});
    return WebAppShell(
      title: 'Student Portal',
      titleIcon: Icons.school_rounded,
      navSections: navSections,
      activeNavId: 'dashboard',
      user: user,
      onLogout: () => _logout(context),
      onSecuritySettings: () => _showSecuritySettings(context),
      contentPadding: EdgeInsets.zero,
      body: content,
    );
  }

  Widget _dashboardContent(
      BuildContext context, AppUser? user, String uid, String academyId) {
    return StreamBuilder<List<ClassEntity>>(
      stream: context.read<ClassProvider>().streamForStudent(uid, academyId),
      builder: (context, classSnap) {
        final classes = classSnap.data ?? [];
        return StreamBuilder<List<TestMarkModel>>(
          stream:
              context.read<QuizProvider>().watchStudentResults(uid, academyId),
          builder: (context, marksSnap) {
            final marks = marksSnap.data ?? [];
            final avgPercent = marks.isEmpty
                ? null
                : marks.map((m) => m.percentage).reduce((a, b) => a + b) /
                    marks.length;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _welcomeCard(context, user, classes),
                const SizedBox(height: 12),
                LatestAnnouncementCard(
                  role: 'student',
                  academyId: academyId,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ViewAnnouncementsScreen())),
                ),
                const SizedBox(height: 20),
                _sectionLabel(context, 'QUICK STATISTICS'),
                const SizedBox(height: 10),
                _quickStatsGrid(
                    context, uid, academyId, classes.length, avgPercent),
                const SizedBox(height: 20),
                _progressCard(context, avgPercent),
                const SizedBox(height: 20),
                _sectionLabel(context, 'QUICK ACTIONS'),
                const SizedBox(height: 10),
                _quickActionsRow(context, user),
                const SizedBox(height: 20),
                _sectionLabel(context, 'LEARNING'),
                const SizedBox(height: 10),
                _moduleGroup(context, Icons.menu_book_rounded, [
                  _ModuleItem(
                      'Assignments',
                      'View, submit and track your work',
                      Icons.assignment_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AssignmentsScreen()))),
                  _ModuleItem(
                      'Academy Location',
                      'Address, map and directions',
                      Icons.place_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AcademyLocationScreen()))),
                  _ModuleItem(
                      'My Documents',
                      'Admission papers and certificates',
                      Icons.folder_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DocumentsScreen(
                                  title: 'My Documents',
                                  category: FileCategory.studentDocument,
                                  ownerId: user?.uid ?? '')))),
                  _ModuleItem(
                      'My Classroom Hub',
                      'Teacher resources & discussions',
                      Icons.school_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MyClassroomHub()))),
                  _ModuleItem(
                      'AI Notes Summarizer',
                      'Instantly summarize notes (100% Offline)',
                      Icons.auto_awesome_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AiSummarizerScreen()))),
                ]),
                const SizedBox(height: 16),
                _sectionLabel(context, 'DAILY'),
                const SizedBox(height: 10),
                _moduleGroup(context, Icons.today_rounded, [
                  _ModuleItem(
                      'My Timetable',
                      'View your weekly class schedule',
                      Icons.schedule_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MyTimetableScreen()))),
                  _ModuleItem(
                      'My Attendance',
                      'Track your daily presence and percentage',
                      Icons.fact_check_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  StudentAttendanceScreen(studentUid: uid)))),
                ]),
                const SizedBox(height: 16),
                _sectionLabel(context, 'PERFORMANCE'),
                const SizedBox(height: 10),
                _moduleGroup(context, Icons.insights_rounded, [
                  _ModuleItem(
                      'Test Reports',
                      'Check your marks and performance',
                      Icons.analytics_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => StudentTestReportScreen(
                                  studentUid: uid,
                                  studentName: user?.fullName ?? 'Student')))),
                  _ModuleItem(
                      'Performance Analytics',
                      'Visual progress charts and trends',
                      Icons.show_chart_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => StudentProgressChartScreen(
                                  studentUid: uid)))),
                ]),
                const SizedBox(height: 16),
                _sectionLabel(context, 'ACADEMY'),
                const SizedBox(height: 10),
                _moduleGroup(context, Icons.account_balance_rounded, [
                  _ModuleItem(
                      'Announcements',
                      'View broadcasts from your academy',
                      Icons.campaign_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const ViewAnnouncementsScreen()))),
                  _ModuleItem(
                      'Fee Status',
                      'View your payment history and dues',
                      Icons.receipt_long_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  StudentFeeScreen(studentUid: uid)))),
                ]),
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(text,
      style: TextStyle(
          color: context.appColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2));

  Widget _welcomeCard(
      BuildContext context, dynamic user, List<ClassEntity> classes) {
    final name = user?.fullName ?? 'Student';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final classLabel = classes.isNotEmpty
        ? '${classes.first.className} - ${classes.first.section}'
        : '';
    final rollNumber = (user?.rollNumber ?? '') as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.accent.withValues(alpha: 0.12),
              child: Text(initial,
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_greeting()}, $name',
                      style: TextStyle(
                          color: context.appColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  if (classLabel.isNotEmpty || rollNumber.isNotEmpty)
                    Text(
                        [
                          if (classLabel.isNotEmpty) classLabel,
                          if (rollNumber.isNotEmpty) 'Roll No: $rollNumber',
                        ].join(' • '),
                        style: TextStyle(
                            color: context.appColors.textSecondary,
                            fontSize: 13)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: context.appColors.surfaceAlt
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: context.appColors.border
                              .withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.format_quote_rounded,
                              color: context.appColors.textMuted, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('"${_quoteOfTheDay()}"',
                              style: TextStyle(
                                  color: context.appColors.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickStatsGrid(BuildContext context, String uid, String academyId,
      int subjectCount, double? avgPercent) {
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<List<dynamic>>(
            stream: context
                .read<AttendanceProvider>()
                .watchStudentAttendance(uid, academyId),
            builder: (context, snap) {
              final records = snap.data ?? [];
              String value = '--';
              if (records.isNotEmpty) {
                final present =
                    records.where((r) => r.isPresent || r.isLate).length;
                value = '${((present / records.length) * 100).round()}%';
              }
              return _statCard(context, Icons.fact_check_rounded,
                  AppColors.success, value, 'Attendance');
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(context, Icons.menu_book_rounded,
              AppColors.accentDark, '$subjectCount', 'Subjects'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
              context,
              Icons.grade_rounded,
              AppColors.accent,
              avgPercent == null ? '--' : '${avgPercent.round()}%',
              'Average Marks'),
        ),
      ],
    );
  }

  Widget _statCard(BuildContext context, IconData icon, Color color,
      String value, String label) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            // Three cards share a 320 px row: scale single long words (e.g.
            // "Attendance") down slightly instead of splitting them.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label,
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard(BuildContext context, double? avgPercent) {
    final progress = ((avgPercent ?? 0) / 100).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded,
                    color: context.appColors.accentText, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Overall Performance',
                      style: TextStyle(
                          color: context.appColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text(
                    avgPercent == null
                        ? 'No data yet'
                        : '${avgPercent.round()}%',
                    style: TextStyle(
                        color: context.appColors.accentText,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor:
                    context.appColors.border.withValues(alpha: 0.4),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionsRow(BuildContext context, dynamic user) {
    final uid = user?.uid ?? '';
    final actions = [
      _ModuleItem(
          'Timetable',
          '',
          Icons.schedule_rounded,
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MyTimetableScreen()))),
      _ModuleItem(
          'Results',
          '',
          Icons.analytics_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StudentTestReportScreen(
                      studentUid: uid,
                      studentName: user?.fullName ?? 'Student')))),
      _ModuleItem(
          'Announcements',
          '',
          Icons.campaign_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ViewAnnouncementsScreen()))),
      _ModuleItem(
          'AI Notes',
          '',
          Icons.auto_awesome_rounded,
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AiSummarizerScreen()))),
    ];
    return Row(
      children: actions
          .map((a) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: a.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(a.icon,
                                color: context.appColors.accentText, size: 22),
                            const SizedBox(height: 6),
                            Text(a.title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: context.appColors.textPrimary,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _moduleGroup(
      BuildContext context, IconData groupIcon, List<_ModuleItem> items) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(items[i].icon,
                    color: context.appColors.accentText, size: 20),
              ),
              title: Text(items[i].title,
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              subtitle: Text(items[i].subtitle,
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 12)),
              trailing:
                  Icon(Icons.chevron_right, color: context.appColors.textMuted),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }

  Widget _notificationBell(BuildContext context, dynamic user) {
    if (user == null) return const SizedBox();
    return StreamBuilder<List<dynamic>>(
      stream:
          NotificationService().watchForUser(user.uid, user.academyId ?? ''),
      builder: (context, snap) {
        final count =
            snap.hasData ? snap.data!.where((n) => !n.isRead).length : 0;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_rounded,
                  color: context.appColors.accentText),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen())),
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: AppColors.danger, shape: BoxShape.circle),
                  child: Text('$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showSecuritySettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Security Settings",
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text("Enhance your account security with biometric authentication.",
                style: TextStyle(
                    color: context.appColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 24),
            StatefulBuilder(
              builder: (context, setInternalState) {
                final session = context.watch<SessionProvider>();
                return SwitchListTile(
                  title: Text("Biometric / Face Unlock",
                      style: TextStyle(
                          color: context.appColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: const Text("Use fingerprints or face ID to log in.",
                      style: TextStyle(fontSize: 12)),
                  value: session.biometricEnabled,
                  activeThumbColor: AppColors.accent,
                  onChanged: (val) async {
                    if (val) {
                      final authenticated =
                          await session.authenticateWithBiometrics();
                      if (!context.mounted) return;
                      if (authenticated) {
                        final pass = await _promptForPassword(context);
                        if (pass != null) {
                          await session.setBiometricEnabled(true,
                              password: pass);
                        }
                      }
                    } else {
                      await session.setBiometricEnabled(false);
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showChangePasswordDialog(context),
              icon: const Icon(Icons.lock_reset_rounded),
              label: const Text("Change Account Password"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                foregroundColor: AppColors.accent,
                elevation: 0,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.accent)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showSecurityQuestionDialog(
                context,
                Provider.of<AuthProvider>(context, listen: false).currentUser,
              ),
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text("Update Recovery Question"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showAcademyRelinkDialog(context),
              icon: const Icon(Icons.sync_problem_rounded),
              label: const Text("Fix Academy Link"),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.appColors.textSecondary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: context.appColors.border),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final currentPasswordCtrl = TextEditingController();
    bool showPassword = false;
    bool showConfirmation = false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: const Text("Change Password"),
        content: StatefulBuilder(
            builder: (ctx, setDialogState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LabeledField(
                        label: "Current Password",
                        hint: "Verify your current password",
                        controller: currentPasswordCtrl,
                        obscure: true),
                    const SizedBox(height: 12),
                    Text("Enter a new password for your account.",
                        style: TextStyle(
                            color: context.appColors.textSecondary,
                            fontSize: 13)),
                    const SizedBox(height: 20),
                    LabeledField(
                        label: "New Password",
                        hint: "At least 8 characters",
                        controller: passCtrl,
                        obscure: !showPassword,
                        suffix: IconButton(
                          icon: Icon(showPassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setDialogState(
                              () => showPassword = !showPassword),
                        )),
                    LabeledField(
                        label: "Confirm Password",
                        hint: "Re-enter",
                        controller: confirmCtrl,
                        obscure: !showConfirmation,
                        suffix: IconButton(
                          icon: Icon(showConfirmation
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setDialogState(
                              () => showConfirmation = !showConfirmation),
                        )),
                  ],
                )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              if (passCtrl.text != confirmCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Passwords do not match!")));
                return;
              }
              if (passCtrl.text.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Minimum 8 characters required!")));
                return;
              }
              try {
                await AuthService().directUpdatePassword(passCtrl.text,
                    currentPassword: currentPasswordCtrl.text);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Password updated successfully!")));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("UPDATE",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForPassword(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;
    bool verifying = false;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.appColors.surface,
          title: const Text("Verify Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Enter your account password to enable biometric login.",
                  style: TextStyle(
                      fontSize: 13, color: context.appColors.textSecondary)),
              const SizedBox(height: 16),
              LabeledField(
                  label: "Current Password",
                  hint: "Required",
                  controller: ctrl,
                  obscure: true),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CANCEL")),
            TextButton(
              onPressed: verifying
                  ? null
                  : () async {
                      setDialogState(() {
                        verifying = true;
                        error = null;
                      });
                      final ok = await AuthService().verifyPassword(ctrl.text);
                      if (!ok) {
                        setDialogState(() {
                          verifying = false;
                          error = "Incorrect password.";
                        });
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx, ctrl.text);
                    },
              child: Text(verifying ? "VERIFYING..." : "VERIFY",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.appColors.accentText)),
            ),
          ],
        ),
      ),
    );
  }
}
