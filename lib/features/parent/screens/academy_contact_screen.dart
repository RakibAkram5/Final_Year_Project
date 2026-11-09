import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../shared/academy_location.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class AcademyContactScreen extends StatelessWidget {
  final String academyId;
  const AcademyContactScreen({super.key, required this.academyId});

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
        title: const Text('Academy Support',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
      title: 'Academy Support',
      titleIcon: Icons.support_agent_rounded,
      navSections: navSections,
      activeNavId: 'academy_support',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    // The signed-in user's profile (/auth/me) already carries their own
    // academy's details. (Previously this looked up a *user* whose id was the
    // academy id, which never exists, so the screen always showed
    // "Academy profile unavailable".)
    return Builder(
      builder: (context) {
        final academy = context.watch<AuthProvider>().currentUser;
        final name = academy?.academyName ?? "Academy profile unavailable";
        final address = academy?.academyAddress ?? "Address not provided";
        final phone = academy?.academyPhone ?? "";

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildHeader(context, name),
            const SizedBox(height: 16),
            AcademyLocationCard(user: academy),
            const SizedBox(height: 24),
            Text('CONTACT CHANNELS',
                style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 16),
            _contactTile(
              context,
              'Official WhatsApp',
              phone,
              Icons.chat_bubble_rounded,
              AppColors.success,
              phone.isEmpty ? null : () => _openWhatsApp(context, phone),
            ),
            const SizedBox(height: 12),
            _contactTile(
              context,
              'Helpline / Call',
              phone,
              Icons.call_rounded,
              AppColors.accent,
              phone.isEmpty ? null : () => _callNumber(context, phone),
            ),
            const SizedBox(height: 32),
            _buildLocationCard(context, address),
          ],
        );
      },
    );
  }

  Future<void> _callNumber(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), ''));
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open the dialer.")));
    }
  }

  Future<void> _openWhatsApp(BuildContext context, String phone) async {
    // wa.me expects digits only, with country code and no leading zero/+.
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = '92${digits.substring(1)}'; // Pakistan local -> country code
    }
    final uri = Uri.parse('https://wa.me/$digits');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open WhatsApp.")));
    }
  }

  Widget _buildHeader(BuildContext context, String name) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(Icons.school_rounded,
              size: 48, color: context.appColors.accentText),
        ),
        const SizedBox(height: 16),
        Text(name,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: context.appColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900)),
        Text('Education with Excellence',
            style: TextStyle(color: context.appColors.textMuted)),
      ],
    );
  }

  Widget _contactTile(BuildContext context, String title, String val,
      IconData icon, Color color, VoidCallback? onTap) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            onTap: onTap,
            leading: Icon(icon, color: color),
            title: Text(title,
                style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            subtitle: Text(val.isEmpty ? 'Not configured' : val,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            trailing: onTap == null
                ? null
                : Icon(Icons.open_in_new_rounded,
                    size: 18, color: context.appColors.textMuted),
          )),
    );
  }

  Widget _buildLocationCard(BuildContext context, String address) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.danger, size: 20),
              const SizedBox(width: 8),
              Text('Location',
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(address,
              style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                  height: 1.4)),
          const SizedBox(height: 16),
          Text('VISTING HOURS',
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          Text('Mon - Fri (09:00 AM - 05:00 PM)',
              style: TextStyle(
                  color: context.appColors.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }
}
