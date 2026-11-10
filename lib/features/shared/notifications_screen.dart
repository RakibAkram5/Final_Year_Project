import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../logic/auth_provider.dart';
import '../../data/models/notification_model.dart';
import '../../data/remote/notification_service.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final uid = user?.uid ?? '';
    final academyId = user?.academyId ?? '';

    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context, user, uid, academyId);
    }
    return _buildMobileLayout(context, uid, academyId);
  }

  Widget _buildMobileLayout(
      BuildContext context, String uid, String academyId) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        actions: [
          if (uid.isNotEmpty)
            StreamBuilder<List<NotificationModel>>(
              stream: _service.watchForUser(uid, academyId),
              builder: (context, snap) {
                final list = snap.data ?? const [];
                final hasUnread = list.any((n) => !n.isRead);
                if (!hasUnread) return const SizedBox.shrink();
                return TextButton(
                  onPressed: () => _markAllAsRead(uid, academyId),
                  child: Text("Mark all as read",
                      style: TextStyle(color: context.appColors.accentText)),
                );
              },
            ),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(uid, academyId),
        ),
      ),
    );
  }

  /// Every role can open this screen from its topbar bell, so the sidebar
  /// mirrors whichever role is currently logged in — same idea as
  /// [TimetableView]'s `webNavSections` parameter, just resolved internally
  /// here since this screen already reads [AuthProvider] for its data.
  Widget _buildWebLayout(
      BuildContext context, AppUser? user, String uid, String academyId) {
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
      title: 'Notifications',
      titleIcon: Icons.notifications_rounded,
      navSections: navSections,
      activeNavId: 'notifications',
      user: user,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Notifications',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800)),
                  ),
                  if (uid.isNotEmpty)
                    StreamBuilder<List<NotificationModel>>(
                      stream: _service.watchForUser(uid, academyId),
                      builder: (context, snap) {
                        final list = snap.data ?? const [];
                        final hasUnread = list.any((n) => !n.isRead);
                        if (!hasUnread) return const SizedBox.shrink();
                        return TextButton(
                          onPressed: () => _markAllAsRead(uid, academyId),
                          child: Text("Mark all as read",
                              style: TextStyle(
                                  color: context.appColors.accentText)),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(child: _body(uid, academyId)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(String uid, String academyId) {
    return uid.isEmpty
        ? _buildEmptyState('Please log in again.')
        : StreamBuilder<List<NotificationModel>>(
            stream: _service.watchForUser(uid, academyId),
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
                      'Error loading notifications: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                );
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return _buildEmptyState('No notifications yet');
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) => _notifTile(ctx, list[i]),
              );
            },
          );
  }

  Future<void> _markAllAsRead(String uid, String academyId) async {
    try {
      await _service.markAllAsRead(uid, academyId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Failed to mark notifications as read: $e"),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await _service.markAsRead(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Failed to update notification: $e"),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 64, color: context.appColors.textMuted),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _notifTile(BuildContext context, NotificationModel n) {
    return InkWell(
      onTap: () {
        if (!n.isRead) _markAsRead(n.id);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: n.isRead
              ? Colors.transparent
              : AppColors.accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: n.isRead
                  ? context.appColors.border.withValues(alpha: 0.5)
                  : AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _colorFor(n.type).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(n.type), color: _colorFor(n.type), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: TextStyle(
                          color: context.appColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(n.message,
                      style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 13,
                          height: 1.4)),
                  const SizedBox(height: 8),
                  Text(DateFormat('d MMM, h:mm a').format(n.createdAt),
                      style: TextStyle(
                          color: context.appColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (!n.isRead)
              const CircleAvatar(radius: 4, backgroundColor: AppColors.accent),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'approval':
        return Icons.verified_user_rounded;
      case 'fee':
        return Icons.payments_rounded;
      case 'attendance':
        return Icons.fact_check_rounded;
      case 'result':
        return Icons.analytics_rounded;
      case 'announcement':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'approval':
        return AppColors.success;
      case 'fee':
        return Colors.orange;
      case 'attendance':
        return AppColors.accent;
      case 'result':
        return Colors.purple;
      case 'announcement':
        return AppColors.accent;
      default:
        return context.appColors.textSecondary;
    }
  }
}
