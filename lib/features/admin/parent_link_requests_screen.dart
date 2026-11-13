import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/parent_link_request.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';

/// Admin screen to review parent→child link requests. The admin verifies the
/// matched student and approves (which creates the link) or rejects. All data
/// is academy-scoped by the backend.
class ParentLinkRequestsScreen extends StatefulWidget {
  const ParentLinkRequestsScreen({super.key});

  @override
  State<ParentLinkRequestsScreen> createState() =>
      _ParentLinkRequestsScreenState();
}

class _ParentLinkRequestsScreenState extends State<ParentLinkRequestsScreen>
    with SingleTickerProviderStateMixin {
  static const _statuses = ['PENDING', 'APPROVED', 'REJECTED'];
  late final TabController _tabs =
      TabController(length: _statuses.length, vsync: this)
        ..addListener(() {
          if (!_tabs.indexIsChanging) _load();
        });

  bool _loading = true;
  String? _error;
  List<ParentLinkRequest> _requests = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _status => _statuses[_tabs.index];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AuthService().getLinkRequests(status: _status);
      if (!mounted) return;
      setState(() => _requests = rows);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load requests. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(ParentLinkRequest r) async {
    setState(() => _busy.add(r.id));
    try {
      await AuthService()
          .approveLinkRequest(r.id, studentId: r.matchedStudent?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request approved and child linked.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _reject(ParentLinkRequest r) async {
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Reject request'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Shown to the parent',
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
    if (note == null) return; // cancelled
    setState(() => _busy.add(r.id));
    try {
      await AuthService().rejectLinkRequest(r.id, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Request rejected.')));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Link Requests'),
        bottom: TabBar(
          controller: _tabs,
          tabs: _statuses
              .map((s) => Tab(text: '${s[0]}${s.substring(1).toLowerCase()}'))
              .toList(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 48),
          Center(child: Text(_error!)),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_requests.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 64),
          Center(child: Text('No ${_status.toLowerCase()} requests.')),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _requests.length,
      itemBuilder: (_, i) => _buildCard(_requests[i]),
    );
  }

  Widget _buildCard(ParentLinkRequest r) {
    final busy = _busy.contains(r.id);
    final student = r.matchedStudent;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Child: ${r.childName}',
                      style: theme.textTheme.titleMedium),
                ),
                _StatusChip(status: r.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                [
                  if (r.childEmail?.isNotEmpty ?? false) r.childEmail,
                  if (r.rollNumber?.isNotEmpty ?? false) 'Roll ${r.rollNumber}',
                ].whereType<String>().join(' · '),
                style: theme.textTheme.bodySmall),
            const Divider(height: 18),
            Text(
                'Requested by: ${r.parent?.fullName ?? '—'}'
                '${r.parent?.email != null ? ' (${r.parent!.email})' : ''}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            if (student != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: AppColors.accentDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Matched: ${student.fullName ?? '—'}'
                        '${student.rollNumber != null ? ' · Roll ${student.rollNumber}' : ''}'
                        '${student.email != null ? ' · ${student.email}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'No automatic match — verify the details with the parent before approving.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.danger),
              ),
            if (r.isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => _reject(r),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed:
                        busy || student == null ? null : () => _approve(r),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    label: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    switch (status) {
      case 'APPROVED':
        color = Colors.green;
        break;
      case 'REJECTED':
        color = AppColors.danger;
        break;
      default:
        color = AppColors.accentDark;
    }
    return Chip(
      label: Text(status, style: const TextStyle(fontSize: 11)),
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
