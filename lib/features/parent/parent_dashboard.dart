import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../logic/auth_provider.dart';
import '../../logic/parent_provider.dart';
import '../../logic/session_provider.dart'; // NEW
import '../../data/models/app_user.dart';
import '../../data/remote/auth_service.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/dashboard_app_bar_actions.dart';
import '../../widgets/parent_stats_row.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';
import '../../data/remote/notification_service.dart';
import '../shared/notifications_screen.dart';
import '../../widgets/gradient_background.dart';
import '../shared/view_announcements_screen.dart';
import 'screens/child_overview_screen.dart';
import 'screens/child_timetable_screen.dart';
import 'screens/all_challans_screen.dart';
import 'screens/academy_contact_screen.dart'; // NEW
import '../../widgets/academy_relink_dialog.dart';
import '../../widgets/security_question_dialog.dart';
import 'link_child_request_screen.dart';

class ParentDashboard extends StatelessWidget {
  const ParentDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final parentProv = context.watch<ParentProvider>();

    final content = _dashboardContent(context, user, parentProv);

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
            Icon(Icons.family_restroom_rounded,
                color: context.appColors.accentText, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Parent Portal',
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
    final navSections = buildParentNavSections(context, onDashboard: () {});
    return WebAppShell(
      title: 'Parent Portal',
      titleIcon: Icons.family_restroom_rounded,
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
      BuildContext context, AppUser? user, ParentProvider parentProv) {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => parentProv.refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          // Long names wrap instead of being shrunk to an unreadable size.
          Text('Welcome, ${user?.fullName ?? 'Parent'}',
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Monitor your child\'s education journey',
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 20),
          ParentStatsRow(
              children: parentProv.children, academyId: user?.academyId ?? ''),
          const SizedBox(height: 28),
          Text('MY CHILDREN',
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          if (parentProv.loading && parentProv.children.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: AppColors.accent)))
          else if (parentProv.error != null && parentProv.children.isEmpty)
            _loadErrorCard(context, parentProv)
          else if (parentProv.children.isEmpty)
            _noChildrenPlaceholder(context)
          else
            ...parentProv.children.map((c) => _childCard(context, c)),
          const SizedBox(height: 32),
          Text('SERVICES',
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          _actionTile(
            context,
            'Fee Challans',
            'Download and pay monthly invoices',
            Icons.receipt_long_rounded,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AllChallansScreen())),
          ),
          const SizedBox(height: 12),
          _actionTile(
            context,
            'Announcements',
            'General broadcasts and notices',
            Icons.campaign_rounded,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ViewAnnouncementsScreen())),
          ),
          const SizedBox(height: 12),
          _actionTile(
            context,
            'Academy Support',
            'Contact management and helpdesk',
            Icons.support_agent_rounded,
            () {
              if (parentProv.children.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Please link a child first.")));
                return;
              }
              final firstChild = parentProv.children.first;
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AcademyContactScreen(
                          academyId: firstChild.academyId ?? '')));
            },
          ),
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LinkChildRequestScreen()),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text("Link a Child"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                elevation: 0,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
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

  Widget _childCard(BuildContext context, AppUser child) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.accent.withValues(alpha: 0.1),
          child: Text(
              child.fullName.isNotEmpty ? child.fullName[0].toUpperCase() : '?',
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(child.fullName,
            style: TextStyle(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.bold)),
        subtitle: Text(child.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        trailing: PopupMenuButton<String>(
          icon:
              Icon(Icons.more_vert_rounded, color: context.appColors.textMuted),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) {
            if (val == 'view') {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ChildOverviewScreen(child: child)));
            } else if (val == 'timetable') {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ChildTimetableScreen(child: child)));
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
                value: 'view',
                child: Row(children: [
                  Icon(Icons.visibility_rounded, size: 18),
                  SizedBox(width: 12),
                  Text("View Details")
                ])),
            const PopupMenuItem(
                value: 'timetable',
                child: Row(children: [
                  Icon(Icons.schedule_rounded, size: 18),
                  SizedBox(width: 12),
                  Text("View Timetable")
                ])),
          ],
        ),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChildOverviewScreen(child: child))),
      ),
    );
  }

  Widget _loadErrorCard(BuildContext context, ParentProvider parentProv) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 40, color: AppColors.danger),
          const SizedBox(height: 12),
          Text(parentProv.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: parentProv.loading ? null : () => parentProv.refresh(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noChildrenPlaceholder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: context.appColors.border.withValues(alpha: 0.3),
            style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(Icons.child_care_rounded,
              size: 48,
              color: context.appColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text("No children linked yet",
              style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("Your academy will link your child's profile to your account.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, String title, String subtitle,
      IconData icon, VoidCallback onTap) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(icon, color: context.appColors.accentText, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.w700)),
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
