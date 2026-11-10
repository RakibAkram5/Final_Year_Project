import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/parent_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import 'student_challan_screen.dart';

class AllChallansScreen extends StatelessWidget {
  const AllChallansScreen({super.key});

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
        title: const Text('Fee Challans',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
      title: 'Fee Challans',
      titleIcon: Icons.receipt_long_rounded,
      navSections: navSections,
      activeNavId: 'fee_challans',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final children = context.watch<ParentProvider>().children;
    return children.isEmpty
        ? _buildNoChildrenState(context)
        : ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, i) {
              final child = children[i];
              return _childChallanTile(context, child);
            },
          );
  }

  Widget _childChallanTile(BuildContext context, dynamic child) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              CircleAvatar(
                backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                child: Text(
                  child.fullName.isNotEmpty
                      ? child.fullName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.fullName,
                        style: TextStyle(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text("Student Profile",
                        style: TextStyle(
                            color: context.appColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StudentChallanScreen(studentUid: child.uid)),
            ),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text("VIEW CHALLAN"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textOnAccent,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoChildrenState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.child_care_rounded,
                size: 64, color: context.appColors.textMuted),
            const SizedBox(height: 16),
            Text("No children linked",
                style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontWeight: FontWeight.bold)),
            Text("Please link a child first to see their fee challans.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.appColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
