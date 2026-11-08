import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../data/remote/auth_service.dart';
import '../../logic/auth_provider.dart';
import '../../logic/member_provider.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

/// Admin screen: list users waiting for approval and approve/reject them.
class ApprovalRequestsScreen extends StatefulWidget {
  const ApprovalRequestsScreen({super.key});

  @override
  State<ApprovalRequestsScreen> createState() => _ApprovalRequestsScreenState();
}

class _ApprovalRequestsScreenState extends State<ApprovalRequestsScreen> {
  final _authService = AuthService();
  List<AppUser> _pending = [];
  bool _loading = true;
  String? _error;
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final academyId = auth.currentUser?.uid ?? '';
      final list = await _authService.getPendingUsers(academyId);
      if (!mounted) return;
      setState(() {
        _pending = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load requests. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _approve(AppUser u) async {
    if (_processingIds.contains(u.uid)) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final admin = auth.currentUser;
    if (admin == null) return;

    setState(() => _processingIds.add(u.uid));
    try {
      // The server activates the account in this admin's academy and
      // creates the user's "Account Approved" notification atomically.
      await _authService.approveUser(u.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${u.fullName} approved for your academy')),
        );
        // Refresh global counts
        Provider.of<MemberProvider>(context, listen: false).load(admin.uid);
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to approve ${u.fullName}: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(u.uid));
    }
  }

  Future<void> _confirmReject(AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reject this request?'),
        content: Text(
            "This will reject ${u.fullName}'s signup request. They will be "
            "notified and won't be able to log in."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _reject(u);
    }
  }

  Future<void> _reject(AppUser u) async {
    if (_processingIds.contains(u.uid)) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final admin = auth.currentUser;
    if (admin == null) return;

    setState(() => _processingIds.add(u.uid));
    try {
      // Only change the status; keep the record for admin history. A
      // rejected user cannot sign in, so the login screen tells them.
      await _authService.rejectUser(u.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${u.fullName} rejected')),
        );
        // Refresh global counts for THIS academy
        Provider.of<MemberProvider>(context, listen: false).load(admin.uid);
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to reject ${u.fullName}: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(u.uid));
    }
  }

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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Approval Requests',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: _load,
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Approval Requests',
      titleIcon: Icons.how_to_reg_rounded,
      navSections: navSections,
      activeNavId: 'approvals',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(_error!,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      );
    }
    if (_pending.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(Icons.done_all_rounded,
                    size: 56, color: AppColors.textMuted),
                SizedBox(height: 12),
                Text('No pending requests',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _requestTile(_pending[i]),
    );
  }

  Widget _requestTile(AppUser u) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                child: Text(
                  u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.fullName,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                    Text(u.role.label,
                        style: const TextStyle(
                            color: AppColors.accent, fontSize: 12)),
                    Text(u.email,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                  onPressed: _processingIds.contains(u.uid)
                      ? null
                      : () => _confirmReject(u),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textOnAccent,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  onPressed:
                      _processingIds.contains(u.uid) ? null : () => _approve(u),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
