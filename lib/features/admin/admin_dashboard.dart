import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../data/remote/auth_service.dart';
import '../../logic/auth_provider.dart';
import '../../logic/member_provider.dart';
import '../../logic/session_provider.dart';
import '../../data/remote/notification_service.dart';
import '../../widgets/admin_extra_stats_row.dart';
import '../../widgets/dashboard_app_bar_actions.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/web/web_cards.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';
import '../shared/notifications_screen.dart'; // NEW
import '../../widgets/gradient_background.dart';
import '../../widgets/responsive/responsive_grid.dart';
import '../../widgets/security_question_dialog.dart';
import '../../core/theme/theme_extensions.dart';
import 'user_management_screen.dart';
import 'approval_requests_screen.dart';
import 'parent_link_requests_screen.dart';
import 'fee_ledger_screen.dart';
import 'announcements_screen.dart';
import 'class_management_screen.dart';
import 'class_sections_screen.dart';
import 'admin_quiz_list_screen.dart';
import 'admin_ai_prediction_screen.dart';
import 'screens/challan_generation_screen.dart';
import 'screens/unpaid_students_screen.dart';
import 'screens/timetable_management_screen.dart';
import 'screens/academic_structure_screen.dart';
import '../shared/assignments_screen.dart';
import '../shared/reports_screen.dart';
import '../shared/academy_location.dart';
import 'screens/class_reports_screen.dart';
import 'screens/academy_payment_settings_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final members = Provider.of<MemberProvider>(context, listen: false);
        final user = auth.currentUser;
        if (user != null) {
          members.load(user.uid);
          _scheduleLegacyAdminDataCheck(user);
        }
      }
    });
  }

  /// Runs the legacy academy-data fix outside the startup window. This only
  /// affects old accounts missing an Academy Code/ID, so there is no reason to
  /// compete with the dashboard's first paint and data loads.
  void _scheduleLegacyAdminDataCheck(AppUser user) {
    if (user.academyCode != null && user.academyId != null) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _verifyLegacyAdminData(user);
    });
  }

  /// The server always assigns an academy id and code, so a profile missing
  /// either is a stale local cache: refresh it from `/auth/me` instead of
  /// writing placeholder academy data. Runs unawaited from initState.
  Future<void> _verifyLegacyAdminData(AppUser user) async {
    if (user.academyCode == null || user.academyId == null) {
      try {
        await context.read<AuthProvider>().tryRestoreSession();
      } catch (e) {
        debugPrint('Admin profile refresh failed: $e');
      }
    }
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (r) => false);
    }
  }

  void _showSecuritySettings(BuildContext context) {
    // ... logic remains same
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
    final formKey = GlobalKey<FormState>();
    bool showPassword = false;
    bool showConfirmation = false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: const Text("Change Password"),
        content: Form(
          key: formKey,
          child: Column(
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
                      color: context.appColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 20),
              LabeledField(
                  label: "New Password",
                  hint: "At least 8 characters",
                  controller: passCtrl,
                  obscure: !showPassword,
                  suffix: IconButton(
                    icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setState(() => showPassword = !showPassword),
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
                    onPressed: () =>
                        setState(() => showConfirmation = !showConfirmation),
                  )),
            ],
          ),
        ),
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

  void _showAcademyInfoSettings(BuildContext context, AppUser? user) {
    if (user == null) return;

    final nameCtrl = TextEditingController(text: user.academyName ?? "");
    final addressCtrl = TextEditingController(text: user.academyAddress ?? "");
    final phoneCtrl = TextEditingController(text: user.academyPhone ?? "");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Academy Information",
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                "Update details for official reports and parents support section.",
                style: TextStyle(
                    color: context.appColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 24),
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                backgroundImage: user.academyLogo != null
                    ? NetworkImage(user.academyLogo!)
                    : null,
                child: user.academyLogo == null
                    ? Icon(Icons.business_rounded,
                        color: context.appColors.accentText, size: 32)
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            LabeledField(
                label: "Academy Name",
                hint: "SRS Tech Matrix",
                controller: nameCtrl),
            LabeledField(
                label: "Address",
                hint: "Enter full address",
                controller: addressCtrl),
            LabeledField(
                label: "Contact Number",
                hint: "+92...",
                controller: phoneCtrl,
                keyboardType: TextInputType.phone),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AcademyLocationEditorScreen()));
              },
              icon: const Icon(Icons.add_location_alt_rounded),
              label: Text(user.academyLocation == null
                  ? "Set location on map"
                  : "Change map location"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: "SAVE CHANGES",
              onPressed: () async {
                try {
                  final authProvider = context.read<AuthProvider>();
                  await AuthService().updateAcademyProfile(
                    uid: user.uid,
                    name: nameCtrl.text,
                    address: addressCtrl.text,
                    phone: phoneCtrl.text,
                  );
                  await authProvider.tryRestoreSession();
                  if (ctx.mounted && mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Info updated successfully!")));
                  }
                } catch (error) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('Could not save profile: $error')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final members = context.watch<MemberProvider>();

    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context, user, members);
    }
    return _buildMobileLayout(context, user, members);
  }

  Widget _buildMobileLayout(
      BuildContext context, AppUser? user, MemberProvider members) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded,
                color: context.appColors.accentText, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Admin Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        actions: dashboardAppBarActions(context,
            notificationBell: _notificationBell(context, user),
            onAcademyInfo: () => _showAcademyInfoSettings(context, user),
            onSecurity: () => _showSecuritySettings(context),
            onLogout: _logout),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              if (user != null) {
                await members.load(user.uid);
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Welcome, ${user?.fullName ?? 'Admin'}',
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                if (user?.academyName != null) ...[
                  const SizedBox(height: 4),
                  Text(user!.academyName!,
                      style: TextStyle(
                          color: context.appColors.accentText,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 4),
                Text('Academy overview',
                    style: TextStyle(color: context.appColors.textSecondary)),
                const SizedBox(height: 16),

                // NEW: Display Academy Code for easy sharing
                if (user?.academyCode != null)
                  _buildAcademyCodeCard(user!.academyCode!),

                const SizedBox(height: 20),
                Row(
                  children: [
                    _statCard(
                      'Teachers',
                      members.totalTeachers,
                      Icons.co_present_rounded,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const UserManagementScreen(initialIndex: 0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      'Students',
                      members.totalStudents,
                      Icons.school_rounded,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const UserManagementScreen(initialIndex: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      'Parents',
                      members.totalParents,
                      Icons.family_restroom_rounded,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const UserManagementScreen(initialIndex: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AdminExtraStatsRow(
                  academyId: user?.uid ?? '',
                  onFeeTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FeeLedgerScreen())),
                  onAnnouncementsTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AnnouncementsScreen())),
                ),
                const SizedBox(height: 8),
                _gridSection('PEOPLE', [
                  _gridTile(
                    'User Management',
                    'Teachers, students, parents',
                    Icons.group_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const UserManagementScreen())),
                  ),
                  _gridTile(
                    'Approval Requests',
                    'Approve or reject signups',
                    Icons.how_to_reg_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ApprovalRequestsScreen())),
                  ),
                  _gridTile(
                    'Parent Link Requests',
                    'Review & approve child links',
                    Icons.family_restroom_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ParentLinkRequestsScreen())),
                  ),
                ]),
                _gridSection('ACADEMICS', [
                  _gridTile(
                    'Assignments',
                    'Homework, submissions & grades',
                    Icons.assignment_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AssignmentsScreen())),
                  ),
                  _gridTile(
                    'Academic Structure',
                    'Configure levels & groups',
                    Icons.school_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AcademicStructureScreen())),
                  ),
                  _gridTile(
                    'Classes & Sections',
                    'Manage sections, enroll students',
                    Icons.groups_2_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ClassSectionsScreen())),
                  ),
                  _gridTile(
                    'Class Management',
                    'Assign subjects & teachers',
                    Icons.class_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ClassManagementScreen())),
                  ),
                  _gridTile(
                    'Timetable',
                    'Weekly schedules, conflict checks',
                    Icons.schedule_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TimetableManagementScreen())),
                  ),
                  _gridTile(
                    'Test Reports & Grading',
                    'Student performance & results',
                    Icons.analytics_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AdminQuizListScreen())),
                  ),
                ]),
                _gridSection('FEES', [
                  _gridTile(
                    'Fee Ledger',
                    'Track fees and defaulters',
                    Icons.receipt_long_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FeeLedgerScreen())),
                  ),
                  _gridTile(
                    'Payment Settings',
                    'Manage academy QR and account details',
                    Icons.qr_code_2_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const AcademyPaymentSettingsScreen())),
                  ),
                  _gridTile(
                    'Bulk Fee Challans',
                    'Generate monthly invoices',
                    Icons.request_quote_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChallanGenerationScreen())),
                  ),
                  _gridTile(
                    'Unpaid Students',
                    'Pending/overdue challans',
                    Icons.money_off_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const UnpaidStudentsScreen())),
                  ),
                ]),
                _gridSection('INSIGHTS & COMMUNICATION', [
                  _gridTile(
                    'Reports & Exports',
                    'Attendance, results & fees (PDF/Excel)',
                    Icons.summarize_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReportsScreen())),
                  ),
                  _gridTile(
                    'AI Prediction & Insights',
                    'Risk & revenue trends',
                    Icons.auto_awesome_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AdminAiPredictionScreen())),
                  ),
                  _gridTile(
                    'Announcements',
                    'Broadcast to the academy',
                    Icons.campaign_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AnnouncementsScreen())),
                  ),
                  _gridTile(
                    'Class Reports',
                    'Attendance & fee snapshots',
                    Icons.summarize_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ClassReportsScreen())),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout(
      BuildContext context, AppUser? user, MemberProvider members) {
    final navSections = buildAdminNavSections(context, onDashboard: () {});

    return WebAppShell(
      title: 'Admin Portal',
      titleIcon: Icons.admin_panel_settings_rounded,
      navSections: navSections,
      activeNavId: 'dashboard',
      user: user,
      onLogout: _logout,
      onSecuritySettings: () => _showSecuritySettings(context),
      onAcademyInfo: () => _showAcademyInfoSettings(context, user),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async {
          if (user != null) await members.load(user.uid);
        },
        child: ListView(
          children: [
            Text('Welcome back, ${user?.fullName ?? 'Admin'}',
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
            if (user?.academyName != null) ...[
              const SizedBox(height: 6),
              Text(user!.academyName!,
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 4),
            Text('Here\'s what\'s happening across your academy today.',
                style: TextStyle(color: context.appColors.textSecondary)),
            const SizedBox(height: 24),
            if (user?.academyCode != null)
              _buildAcademyCodeCard(user!.academyCode!),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final stats = [
                WebStatCard(
                  label: 'Teachers',
                  value: '${members.totalTeachers}',
                  icon: Icons.co_present_rounded,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const UserManagementScreen(initialIndex: 0))),
                ),
                WebStatCard(
                  label: 'Students',
                  value: '${members.totalStudents}',
                  icon: Icons.school_rounded,
                  accent: AppColors.success,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const UserManagementScreen(initialIndex: 1))),
                ),
                WebStatCard(
                  label: 'Parents',
                  value: '${members.totalParents}',
                  icon: Icons.family_restroom_rounded,
                  accent: AppColors.warning,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const UserManagementScreen(initialIndex: 2))),
                ),
              ];
              final narrow = constraints.maxWidth < 640;
              return narrow
                  ? Column(
                      children: [
                        for (final s in stats) ...[
                          s,
                          const SizedBox(height: 16),
                        ],
                      ],
                    )
                  : Row(
                      children: [
                        for (int i = 0; i < stats.length; i++) ...[
                          Expanded(child: stats[i]),
                          if (i != stats.length - 1) const SizedBox(width: 16),
                        ],
                      ],
                    );
            }),
            const SizedBox(height: 16),
            AdminExtraStatsRow(
              academyId: user?.uid ?? '',
              onFeeTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FeeLedgerScreen())),
              onAnnouncementsTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AnnouncementsScreen())),
            ),
            const SizedBox(height: 8),
            WebGridSection(title: 'PEOPLE', tiles: [
              WebNavTile(
                title: 'User Management',
                subtitle: 'Teachers, students, parents',
                icon: Icons.group_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UserManagementScreen())),
              ),
              WebNavTile(
                title: 'Approval Requests',
                subtitle: 'Approve or reject signups',
                icon: Icons.how_to_reg_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ApprovalRequestsScreen())),
              ),
            ]),
            WebGridSection(title: 'ACADEMICS', tiles: [
              WebNavTile(
                title: 'Academic Structure',
                subtitle: 'Configure levels & groups',
                icon: Icons.school_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AcademicStructureScreen())),
              ),
              WebNavTile(
                title: 'Classes & Sections',
                subtitle: 'Manage sections, enroll students',
                icon: Icons.groups_2_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ClassSectionsScreen())),
              ),
              WebNavTile(
                title: 'Class Management',
                subtitle: 'Assign subjects & teachers',
                icon: Icons.class_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ClassManagementScreen())),
              ),
              WebNavTile(
                title: 'Timetable',
                subtitle: 'Weekly schedules, conflict checks',
                icon: Icons.schedule_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TimetableManagementScreen())),
              ),
              WebNavTile(
                title: 'Test Reports & Grading',
                subtitle: 'Student performance & results',
                icon: Icons.analytics_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminQuizListScreen())),
              ),
            ]),
            WebGridSection(title: 'FEES', tiles: [
              WebNavTile(
                title: 'Fee Ledger',
                subtitle: 'Track fees and defaulters',
                icon: Icons.receipt_long_rounded,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FeeLedgerScreen())),
              ),
              WebNavTile(
                title: 'Payment Settings',
                subtitle: 'Manage academy QR and account details',
                icon: Icons.qr_code_2_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AcademyPaymentSettingsScreen())),
              ),
              WebNavTile(
                title: 'Bulk Fee Challans',
                subtitle: 'Generate monthly invoices',
                icon: Icons.request_quote_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ChallanGenerationScreen())),
              ),
              WebNavTile(
                title: 'Unpaid Students',
                subtitle: 'Pending/overdue challans',
                icon: Icons.money_off_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UnpaidStudentsScreen())),
              ),
            ]),
            WebGridSection(title: 'INSIGHTS & COMMUNICATION', tiles: [
              WebNavTile(
                title: 'AI Prediction & Insights',
                subtitle: 'Risk & revenue trends',
                icon: Icons.auto_awesome_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminAiPredictionScreen())),
              ),
              WebNavTile(
                title: 'Announcements',
                subtitle: 'Broadcast to the academy',
                icon: Icons.campaign_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AnnouncementsScreen())),
              ),
              WebNavTile(
                title: 'Class Reports',
                subtitle: 'Attendance & fee snapshots',
                icon: Icons.summarize_rounded,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ClassReportsScreen())),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _notificationBell(BuildContext context, AppUser? user) {
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

  Widget _statCard(String label, int value, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(icon, color: context.appColors.accentText, size: 20),
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$value',
                      style: TextStyle(
                          color: context.appColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcademyCodeCard(String code) {
    return Card(
      color: AppColors.accent.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.vpn_key_rounded,
                color: context.appColors.accentText, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ACADEMY JOINING CODE",
                      style: TextStyle(
                          color: context.appColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  Text(code,
                      style: TextStyle(
                          color: context.appColors.accentText,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.copy_all_rounded,
                  color: context.appColors.accentText, size: 20),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Academy Code copied to clipboard!")));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A labeled section of a compact 2-column tile grid — groups related
  /// dashboard actions so the whole "MANAGE" area no longer scrolls as one
  /// long single-column list of 11 full-width rows.
  Widget _gridSection(String title, List<Widget> tiles) {
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

  Widget _gridTile(
      String title, String subtitle, IconData icon, VoidCallback onTap) {
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
