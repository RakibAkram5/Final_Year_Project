import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/parent_link_request.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/auth_service.dart';

/// Parent-facing screen to request linking an existing child. The parent submits
/// the child's details; an academy admin reviews and approves. The parent never
/// links directly (that was a security hole — see the parent portal fix).
class LinkChildRequestScreen extends StatefulWidget {
  const LinkChildRequestScreen({super.key});

  @override
  State<LinkChildRequestScreen> createState() => _LinkChildRequestScreenState();
}

class _LinkChildRequestScreenState extends State<LinkChildRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _roll = TextEditingController();

  bool _submitting = false;
  bool _loading = true;
  String? _error;
  List<ParentLinkRequest> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _roll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AuthService().getMyLinkRequests();
      if (!mounted) return;
      setState(() => _requests = rows);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _error = 'Could not load your requests. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await AuthService().submitLinkRequest(
        childName: _name.text.trim(),
        childEmail: _email.text.trim(),
        rollNumber: _roll.text.trim(),
      );
      if (!mounted) return;
      _name.clear();
      _email.clear();
      _roll.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request submitted. An admin will review it.'),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit your request.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link a Child')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildForm(context),
                  const SizedBox(height: 24),
                  Text('Your requests',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent)),
                    )
                  else if (_error != null)
                    _ErrorCard(message: _error!, onRetry: _load)
                  else if (_requests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('You have no link requests yet.'),
                    )
                  else
                    ..._requests.map((r) => _RequestTile(request: r)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Enter your child's details",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'An academy admin will verify and approve the link. '
            'Provide the email or roll number so we can match the right student.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Child full name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Child email (optional if roll number given)',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _roll,
            decoration: const InputDecoration(
              labelText: 'Roll number (optional if email given)',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (_) {
              final hasEmail = _email.text.trim().isNotEmpty;
              final hasRoll = _roll.text.trim().isNotEmpty;
              return (hasEmail || hasRoll)
                  ? null
                  : 'Provide an email or a roll number';
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(_submitting ? 'Submitting…' : 'Submit request'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});
  final ParentLinkRequest request;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (request.childEmail != null && request.childEmail!.isNotEmpty)
        request.childEmail!,
      if (request.rollNumber != null && request.rollNumber!.isNotEmpty)
        'Roll ${request.rollNumber}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(request.childName),
        subtitle: Text([
          subtitleParts.join(' · '),
          if (request.isRejected && (request.note?.isNotEmpty ?? false))
            'Reason: ${request.note}',
        ].where((s) => s.isNotEmpty).join('\n')),
        isThreeLine: request.isRejected && (request.note?.isNotEmpty ?? false),
        trailing: _StatusChip(status: request.status),
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
      label: Text(status, style: const TextStyle(fontSize: 12)),
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
