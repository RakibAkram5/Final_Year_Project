import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_theme.dart';
import '../../data/models/app_user.dart';
import '../../data/remote/notification_service.dart';
import '../../features/shared/notifications_screen.dart';
import '../theme_toggle_widget.dart';
import 'web_nav_items.dart';
import 'web_search.dart';

/// The persistent top bar of [WebAppShell]: sidebar toggle (narrow layouts),
/// quick-navigate search, notification bell, Academy Info (admin only),
/// security settings, theme toggle, and the account menu.
class WebTopBar extends StatelessWidget {
  final AppUser? user;
  final List<WebNavSection> navSections;
  final bool showSidebarToggle;
  final VoidCallback onToggleSidebar;
  final VoidCallback onLogout;
  final VoidCallback? onSecuritySettings;
  final VoidCallback? onAcademyInfo;

  const WebTopBar({
    super.key,
    required this.user,
    required this.navSections,
    required this.showSidebarToggle,
    required this.onToggleSidebar,
    required this.onLogout,
    this.onSecuritySettings,
    this.onAcademyInfo,
  });

  @override
  Widget build(BuildContext context) {
    final webColors = context.webColors;
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: webColors.topbarBackground,
        border: Border(
            bottom: BorderSide(
                color: context.appColors.border.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          if (showSidebarToggle) ...[
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Menu',
              onPressed: onToggleSidebar,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(child: WebQuickSearch(navSections: navSections)),
          const SizedBox(width: 8),
          _NotificationBell(user: user),
          if (onAcademyInfo != null)
            IconButton(
              icon: Icon(Icons.business_rounded,
                  color: context.appColors.accentText),
              tooltip: 'Academy Info',
              onPressed: onAcademyInfo,
            ),
          if (onSecuritySettings != null)
            IconButton(
              icon: Icon(Icons.security_rounded,
                  color: context.appColors.accentText),
              tooltip: 'Security Settings',
              onPressed: onSecuritySettings,
            ),
          const ThemeToggle(),
          const SizedBox(width: 10),
          _ProfileMenu(user: user, onLogout: onLogout),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final AppUser? user;
  const _NotificationBell({required this.user});

  @override
  Widget build(BuildContext context) {
    final u = user;
    if (u == null) return const SizedBox();
    return StreamBuilder<List<dynamic>>(
      stream: NotificationService().watchForUser(u.uid, u.academyId ?? ''),
      builder: (context, snap) {
        final count =
            snap.hasData ? snap.data!.where((n) => !n.isRead).length : 0;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_rounded,
                  color: context.appColors.accentText),
              tooltip: 'Notifications',
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
}

class _ProfileMenu extends StatelessWidget {
  final AppUser? user;
  final VoidCallback onLogout;
  const _ProfileMenu({required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final name = user?.fullName ?? 'User';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: context.appColors.surface,
      onSelected: (value) {
        if (value == 'logout') onLogout();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ctx.appColors.textPrimary)),
              Text(user?.role.label ?? '',
                  style: TextStyle(
                      fontSize: 12, color: ctx.appColors.textSecondary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
              SizedBox(width: 10),
              Text('Log out'),
            ],
          ),
        ),
      ],
      child: CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.accent.withValues(alpha: 0.15),
        child: Text(initial,
            style: TextStyle(
                color: context.appColors.accentText,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}
