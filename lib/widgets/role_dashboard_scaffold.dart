import 'package:flutter/material.dart';
import '../core/theme/theme_extensions.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../logic/auth_provider.dart';
import 'gradient_background.dart';

/// A reusable placeholder dashboard. Each role passes its title, icon and
/// the list of feature modules it will eventually contain.
///
/// This is scaffolding for Phase II — real feature screens replace the
/// [features] placeholders in later sprints.
class RoleDashboardScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> features;

  const RoleDashboardScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.features,
  });

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(icon, color: context.appColors.accentText, size: 22),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout_rounded,
                color: context.appColors.textSecondary),
            tooltip: 'Log out',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${user?.fullName ?? 'User'}',
                  style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.role.label ?? '',
                  style: TextStyle(color: context.appColors.textSecondary),
                ),
                const SizedBox(height: 24),
                Text(
                  'MODULES (coming next sprint)',
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: features.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _moduleTile(context, features[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _moduleTile(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.widgets_outlined,
              color: context.appColors.accentText, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
          Icon(Icons.chevron_right, color: context.appColors.textMuted),
        ],
      ),
    );
  }
}
