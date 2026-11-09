import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/announcement.dart';
import '../../data/remote/announcement_service.dart';
import '../../logic/auth_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _service = AnnouncementService();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final academyId = user?.uid ?? '';

    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context, academyId);
    }
    return _buildMobileLayout(context, academyId);
  }

  Widget _buildMobileLayout(BuildContext context, String academyId) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Announcements',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: academyId.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textOnAccent,
              icon: const Icon(Icons.campaign_rounded),
              label: const Text('New Announcement'),
              onPressed: () => _openComposeSheet(academyId),
            ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(academyId),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context, String academyId) {
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Announcements',
      titleIcon: Icons.campaign_rounded,
      navSections: navSections,
      activeNavId: 'announcements',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Announcements',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: context.appColors.textPrimary)),
              ),
              if (academyId.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _openComposeSheet(academyId),
                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: const Text('New Announcement'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textOnAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _body(academyId)),
        ],
      ),
    );
  }

  Widget _body(String academyId) {
    return academyId.isEmpty
        ? const Center(child: Text("Invalid session"))
        : StreamBuilder<List<Announcement>>(
            stream: _service.watchAll(academyId),
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
                    child: Text('Error loading announcements: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger)),
                  ),
                );
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) return _emptyState();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _announcementTile(list[i], academyId),
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
          Text('Tap "New Announcement" to broadcast one',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _announcementTile(Announcement a, String academyId) {
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
              const SizedBox(width: 8),
              IconButton(
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.edit_outlined,
                    color: context.appColors.textSecondary),
                onPressed: () => _openComposeSheet(academyId, existing: a),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => _confirmDelete(a),
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

  Future<void> _confirmDelete(Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: Text('Delete announcement?',
            style: TextStyle(color: context.appColors.textPrimary)),
        content: Text('Remove "${a.title}" for everyone?',
            style: TextStyle(color: context.appColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: context.appColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await _service.delete(a.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Announcement deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to delete announcement: $e'),
              backgroundColor: AppColors.danger));
        }
      }
    }
  }

  void _openComposeSheet(String academyId, {Announcement? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ComposeSheet(
        existing: existing,
        service: _service,
        academyId: academyId,
      ),
    );
  }
}

/// Bottom sheet to create OR edit an announcement.
class _ComposeSheet extends StatefulWidget {
  final Announcement? existing;
  final AnnouncementService service;
  final String academyId;
  const _ComposeSheet(
      {this.existing, required this.service, required this.academyId});

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _messageCtrl;

  bool _sendToAll = true;
  bool _teachers = false;
  bool _students = false;
  bool _parents = false;

  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _messageCtrl = TextEditingController(text: e?.message ?? '');
    if (e != null) {
      if (e.isForAll) {
        _sendToAll = true;
      } else {
        _sendToAll = false;
        _teachers = e.targetRoles.contains('teacher');
        _students = e.targetRoles.contains('student');
        _parents = e.targetRoles.contains('parent');
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  List<String> _resolveTargets() {
    if (_sendToAll) return ['all'];
    return [
      if (_teachers) 'teacher',
      if (_students) 'student',
      if (_parents) 'parent',
    ];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final targets = _resolveTargets();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick at least one audience')),
      );
      return;
    }

    final auth = context.read<AuthProvider>().currentUser;
    if (auth == null) return;

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await widget.service.update(
          id: widget.existing!.id,
          title: _titleCtrl.text,
          message: _messageCtrl.text,
          targetRoles: targets,
        );
      } else {
        await widget.service.create(
          title: _titleCtrl.text,
          message: _messageCtrl.text,
          targetRoles: targets,
          createdByUid: auth.uid,
          createdByName: auth.fullName,
          academyId: widget.academyId,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_isEditing
                  ? 'Announcement updated'
                  : 'Announcement broadcast')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save. Check your connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.appColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(_isEditing ? 'Edit Announcement' : 'New Announcement',
                  style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Title',
                hint: 'e.g. Mock Exams Schedule',
                controller: _titleCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Title is required'
                    : null,
              ),
              Text('Message',
                  style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _messageCtrl,
                minLines: 3,
                maxLines: 6,
                style: TextStyle(color: context.appColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Write your message here...',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Message is required'
                    : null,
              ),
              const SizedBox(height: 16),
              Text('AUDIENCE',
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  )),
              const SizedBox(height: 8),
              _audienceRow(
                label: 'Everyone',
                icon: Icons.groups_rounded,
                selected: _sendToAll,
                onTap: () => setState(() {
                  _sendToAll = true;
                  _teachers = _students = _parents = false;
                }),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _pickChip(
                      label: 'Teachers',
                      selected: !_sendToAll && _teachers,
                      onTap: () => setState(() {
                        _sendToAll = false;
                        _teachers = !_teachers;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _pickChip(
                      label: 'Students',
                      selected: !_sendToAll && _students,
                      onTap: () => setState(() {
                        _sendToAll = false;
                        _students = !_students;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _pickChip(
                      label: 'Parents',
                      selected: !_sendToAll && _parents,
                      onTap: () => setState(() {
                        _sendToAll = false;
                        _parents = !_parents;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isEditing ? 'Save Changes' : 'Broadcast',
                icon: Icons.send_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _audienceRow({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: context.appColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : context.appColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? context.appColors.accentText
                    : context.appColors.textMuted,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: selected
                          ? context.appColors.textPrimary
                          : context.appColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: context.appColors.accentText, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _pickChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.18)
              : context.appColors.inputFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.accent : context.appColors.border),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected
                  ? context.appColors.accentText
                  : context.appColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            )),
      ),
    );
  }
}
