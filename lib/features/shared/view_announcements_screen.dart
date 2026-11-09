import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/announcement.dart';
import '../../data/models/app_user.dart';
import '../../data/remote/announcement_service.dart';
import '../../logic/auth_provider.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

/// Read-only announcements list for Teacher / Student / Parent portals.
/// Automatically filters by the logged-in user's role (plus 'all').
class ViewAnnouncementsScreen extends StatefulWidget {
  const ViewAnnouncementsScreen({super.key});

  @override
  State<ViewAnnouncementsScreen> createState() =>
      _ViewAnnouncementsScreenState();
}

class _ViewAnnouncementsScreenState extends State<ViewAnnouncementsScreen> {
  final _service = AnnouncementService();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final roleValue = user?.role.value ?? '';
    final academyId = user?.academyId ?? '';

    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context, user, roleValue, academyId);
    }
    return _buildMobileLayout(context, roleValue, academyId);
  }

  Widget _buildMobileLayout(
      BuildContext context, String roleValue, String academyId) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Announcements',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(context, roleValue, academyId),
        ),
      ),
    );
  }

  /// Reached from every role's dashboard, so — like [NotificationsScreen] —
  /// the sidebar resolves to whichever role is currently logged in.
  Widget _buildWebLayout(
      BuildContext context, AppUser? user, String roleValue, String academyId) {
    void onDashboard() => Navigator.of(context).popUntil((r) => r.isFirst);
    final navSections = switch (user?.role) {
      UserRole.admin =>
        buildAdminNavSections(context, onDashboard: onDashboard),
      UserRole.teacher =>
        buildTeacherNavSections(context, onDashboard: onDashboard),
      UserRole.student =>
        buildStudentNavSections(context, onDashboard: onDashboard),
      UserRole.parent =>
        buildParentNavSections(context, onDashboard: onDashboard),
      null => const <WebNavSection>[],
    };

    return WebAppShell(
      title: 'Announcements',
      titleIcon: Icons.campaign_rounded,
      navSections: navSections,
      activeNavId: 'view_announcements',
      user: user,
      onLogout: () => performWebLogout(context),
      body: _body(context, roleValue, academyId),
    );
  }

  Widget _body(BuildContext context, String roleValue, String academyId) {
    return roleValue.isEmpty || academyId.isEmpty
        ? Center(
            child: Text('Please log in again.',
                style: TextStyle(color: context.appColors.textSecondary)),
          )
        : StreamBuilder<List<Announcement>>(
            stream: _service.watchForRole(roleValue, academyId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading announcements: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                );
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) return _emptyState();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _announcementTile(list[i]),
              );
            },
          );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined,
              size: 56, color: context.appColors.textMuted),
          const SizedBox(height: 12),
          Text('No announcements yet',
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Announcements from your academy will appear here',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _announcementTile(Announcement a) {
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
                child: Text(a.title,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              _targetChip(a.targetLabel),
            ],
          ),
          const SizedBox(height: 6),
          Text(a.message,
              style: TextStyle(
                  color: context.appColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.person_rounded,
                  size: 14, color: context.appColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(a.createdByName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 11)),
              ),
              const SizedBox(width: 12),
              Icon(Icons.schedule_rounded,
                  size: 14, color: context.appColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                    DateFormat('EEEE, d MMM yyyy, h:mm a').format(a.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: context.appColors.accentText,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }
}
