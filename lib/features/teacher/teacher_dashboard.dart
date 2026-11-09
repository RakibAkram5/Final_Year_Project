import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/assignments_screen.dart';
import '../shared/reports_screen.dart';
import '../shared/academy_location.dart';
import '../shared/documents_screen.dart';
import '../../data/remote/file_service.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../logic/auth_provider.dart';
import '../../logic/session_provider.dart';
import '../../data/remote/auth_service.dart';
import '../../data/remote/notification_service.dart'; // NEW
import '../../widgets/app_widgets.dart';
import '../../widgets/dashboard_app_bar_actions.dart';
import '../../widgets/teacher_stats_row.dart';
import '../../widgets/web/web_cards.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';
import '../shared/notifications_screen.dart'; // NEW
import '../../widgets/gradient_background.dart';
import '../../widgets/responsive/responsive_grid.dart';
import '../../core/theme/theme_extensions.dart'; // NEW
import '../ocr/screens/ocr_history_screen.dart';
import '../ocr/screens/ocr_scanner_screen.dart';
import '../quiz/screens/monthly_report_screen.dart';
import '../quiz/screens/teacher_quiz_list_screen.dart';
import '../shared/view_announcements_screen.dart';
import 'teacher_classes_screen.dart';
import 'teacher_announcements_screen.dart'; // NEW
import 'screens/my_timetable_screen.dart';
import '../../widgets/academy_relink_dialog.dart';
import '../../widgets/security_question_dialog.dart';

class TeacherDashboard extends StatelessWidget {
  const TeacherDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context, user);
    }
    return _buildMobileLayout(context, user);
  }

  Widget _buildMobileLayout(BuildContext context, AppUser? user) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.co_present_rounded,
                color: context.appColors.accentText, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Teacher Portal',
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
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text('Welcome, ${user?.fullName ?? 'Teacher'}',
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Text('Your classroom overview',
                  style: TextStyle(color: context.appColors.textSecondary)),
              const SizedBox(height: 16),
              if (user != null)
                TeacherStatsRow(
                    teacherUid: user.uid, academyId: user.academyId ?? ''),
              const SizedBox(height: 16),
              _gridSection(context, 'CLASSROOM', [
                _gridTile(
                  context,
                  'Attendance',
                  'Mark daily attendance',
                  Icons.fact_check_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TeacherClassesScreen())),
                ),
                _gridTile(
                  context,
                  'My Timetable',
                  'Weekly class schedule',
                  Icons.schedule_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyTimetableScreen())),
                ),
                _gridTile(
                  context,
                  'My Documents',
                  'CV and certificates on file',
                  Icons.folder_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DocumentsScreen(
                              title: 'My Documents',
                              category: FileCategory.teacherDocument,
                              ownerId: user?.uid ?? ''))),
                ),
                _gridTile(
                  context,
                  'Academy Location',
                  'Map and directions',
                  Icons.place_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AcademyLocationScreen())),
                ),
                _gridTile(
                  context,
                  'Reports',
                  'Attendance & results PDF/Excel',
                  Icons.summarize_rounded,
                  () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ReportsScreen())),
                ),
                _gridTile(
                  context,
                  'Assignments',
                  'Set work, review & grade',
                  Icons.assignment_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AssignmentsScreen())),
                ),
                _gridTile(
                  context,
                  'Resources',
                  'Share notes & materials',
                  Icons.folder_shared_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TeacherClassesScreen(
                              jumpTo: ClassJumpTarget.resources))),
                ),
                _gridTile(
                  context,
                  'Queries',
                  'Answer student questions',
                  Icons.forum_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TeacherClassesScreen(
                              jumpTo: ClassJumpTarget.queries))),
                ),
              ]),
              _gridSection(context, 'GRADING & TESTS', [
                _gridTile(
                  context,
                  'Grading & AI Grader',
                  'Enter or AI-grade marks',
                  Icons.add_chart_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const TeacherQuizListScreen(isAiGen: false))),
                ),
                _gridTile(
                  context,
                  'AI Test Generator',
                  'Generate & print tests',
                  Icons.auto_awesome_motion_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const TeacherQuizListScreen(isAiGen: true))),
                ),
                _gridTile(
                  context,
                  'Monthly Performance',
                  'Compiled student results',
                  Icons.insights_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MonthlyReportScreen())),
                ),
              ]),
              _gridSection(context, 'ANNOUNCEMENTS & TOOLS', [
                _gridTile(
                  context,
                  'View Announcements',
                  'Broadcasts from your academy',
                  Icons.campaign_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ViewAnnouncementsScreen())),
                ),
                _gridTile(
                  context,
                  'Manage Announcements',
                  'Reach parents & students',
                  Icons.add_comment_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TeacherAnnouncementsScreen())),
                ),
                _gridTile(
                  context,
                  'OCR Scanner',
                  'Scan digitized notes',
                  Icons.document_scanner_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const OcrScannerScreen())),
                ),
                _gridTile(
                  context,
                  'OCR History',
                  'View scanned documents',
                  Icons.history_rounded,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const OcrHistoryScreen())),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context, AppUser? user) {
    final navSections = buildTeacherNavSections(context, onDashboard: () {});

    return WebAppShell(
      title: 'Teacher Portal',
      titleIcon: Icons.co_present_rounded,
      navSections: navSections,
      activeNavId: 'dashboard',
      user: user,
      onLogout: () => _logout(context),
      onSecuritySettings: () => _showSecuritySettings(context),
      body: ListView(
        children: [
          Text('Welcome back, ${user?.fullName ?? 'Teacher'}',
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Here\'s your classroom overview.',
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 20),
          if (user != null)
            TeacherStatsRow(
                teacherUid: user.uid, academyId: user.academyId ?? ''),
          const SizedBox(height: 24),
          WebGridSection(title: 'CLASSROOM', tiles: [
            WebNavTile(
              title: 'Attendance',
              subtitle: 'Mark daily attendance',
              icon: Icons.fact_check_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherClassesScreen())),
            ),
            WebNavTile(
              title: 'My Timetable',
              subtitle: 'Weekly class schedule',
              icon: Icons.schedule_rounded,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MyTimetableScreen())),
            ),
            WebNavTile(
              title: 'Resources',
              subtitle: 'Share notes & materials',
              icon: Icons.folder_shared_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherClassesScreen(
                          jumpTo: ClassJumpTarget.resources))),
            ),
            WebNavTile(
              title: 'Queries',
              subtitle: 'Answer student questions',
              icon: Icons.forum_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherClassesScreen(
                          jumpTo: ClassJumpTarget.queries))),
            ),
          ]),
          WebGridSection(title: 'GRADING & TESTS', tiles: [
            WebNavTile(
              title: 'Grading & AI Grader',
              subtitle: 'Enter or AI-grade marks',
              icon: Icons.add_chart_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const TeacherQuizListScreen(isAiGen: false))),
            ),
            WebNavTile(
              title: 'AI Test Generator',
              subtitle: 'Generate & print tests',
              icon: Icons.auto_awesome_motion_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const TeacherQuizListScreen(isAiGen: true))),
            ),
            WebNavTile(
              title: 'Monthly Performance',
              subtitle: 'Compiled student results',
              icon: Icons.insights_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MonthlyReportScreen())),
            ),
          ]),
          WebGridSection(title: 'ANNOUNCEMENTS & TOOLS', tiles: [
            WebNavTile(
              title: 'View Announcements',
              subtitle: 'Broadcasts from your academy',
              icon: Icons.campaign_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ViewAnnouncementsScreen())),
            ),
            WebNavTile(
              title: 'Manage Announcements',
              subtitle: 'Reach parents & students',
              icon: Icons.add_comment_rounded,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherAnnouncementsScreen())),
            ),
            WebNavTile(
              title: 'OCR Scanner',
              subtitle: 'Scan digitized notes',
              icon: Icons.document_scanner_rounded,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const OcrScannerScreen())),
            ),
            WebNavTile(
              title: 'OCR History',
              subtitle: 'View scanned documents',
              icon: Icons.history_rounded,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const OcrHistoryScreen())),
            ),
          ]),
        ],
      ),
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

  /// A labeled section of a compact 2-column tile grid — groups related
  /// dashboard actions so the whole "MODULES" area no longer scrolls as one
  /// long single-column list of 11 full-width rows.
  Widget _gridSection(BuildContext context, String title, List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          ResponsiveTileGrid(children: tiles),
        ],
      ),
    );
  }

  Widget _gridTile(BuildContext context, String title, String subtitle,
      IconData icon, VoidCallback onTap) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(icon, color: context.appColors.accentText, size: 18),
              ),
              const Spacer(),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }
}
