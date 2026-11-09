import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/models/class_entity.dart';
import '../../data/models/shared_resource.dart';
import '../../data/remote/classroom_service.dart';
import '../../data/remote/file_service.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/attachments_section.dart';

/// Course materials of one class: notes, slides, worksheets (uploaded files),
/// links and text. Teachers/admins of the class can share and remove
/// materials ([canManage]); students and parents get a read-only view with
/// preview and download. The server enforces the same rules.
class CourseMaterialsView extends StatefulWidget {
  final ClassEntity classEntity;
  final bool canManage;
  const CourseMaterialsView(
      {super.key, required this.classEntity, this.canManage = false});

  @override
  State<CourseMaterialsView> createState() => _CourseMaterialsViewState();
}

class _CourseMaterialsViewState extends State<CourseMaterialsView> {
  final _service = ClassroomService();
  late final Stream<List<SharedResource>> _stream = _service.watchResources(
      widget.classEntity.id, widget.classEntity.academyId);

  Future<void> _share() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ShareMaterialSheet(classEntity: widget.classEntity),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Material shared with the class'),
          backgroundColor: AppColors.success));
    }
  }

  Future<void> _delete(SharedResource r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove material?'),
        content: Text('"${r.title}" and its files will be deleted for '
            'everyone in this class.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteResource(r.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not delete: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return StreamBuilder<List<SharedResource>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <SharedResource>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (widget.canManage)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Share material'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textOnAccent),
                ),
              ),
            if (widget.canManage) const SizedBox(height: 16),
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData)
              const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accent)))
            else if (snap.hasError && list.isEmpty)
              Text('Could not load materials: ${snap.error}',
                  style: const TextStyle(color: AppColors.danger))
            else if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  Icon(Icons.folder_open_rounded,
                      size: 48, color: colors.textMuted.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                      widget.canManage
                          ? 'Nothing shared yet. Upload notes, slides or worksheets.'
                          : 'No materials have been shared for this class yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textSecondary)),
                ]),
              )
            else
              for (final r in list) ...[
                _card(r),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }

  Widget _card(SharedResource r) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.menu_book_rounded,
                  color: context.appColors.accentText, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(r.title,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            if (widget.canManage)
              IconButton(
                tooltip: 'Delete material',
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => _delete(r),
              ),
          ]),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.description,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 6),
          Text(
              '${r.teacherName} · ${DateFormat('d MMM yyyy').format(r.createdAt)}',
              style: TextStyle(color: colors.textMuted, fontSize: 11)),
          if (r.fileUrl != null && r.fileUrl!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openLink(r.fileUrl!),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Open link'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            ),
          const SizedBox(height: 8),
          AttachmentsSection(
            category: FileCategory.courseMaterial,
            ownerId: r.id,
            canEdit: widget.canManage,
            title: 'Files',
            emptyText: 'No files attached.',
          ),
        ],
      ),
    );
  }
}

class _ShareMaterialSheet extends StatefulWidget {
  final ClassEntity classEntity;
  const _ShareMaterialSheet({required this.classEntity});

  @override
  State<_ShareMaterialSheet> createState() => _ShareMaterialSheetState();
}

class _ShareMaterialSheetState extends State<_ShareMaterialSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _link = TextEditingController();
  (String, Uint8List)? _file;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await pickFileFor(context, FileCategory.courseMaterial);
    if (picked != null) {
      setState(() {
        _file = picked;
        if (_title.text.trim().isEmpty) {
          _title.text = picked.$1.replaceAll(RegExp(r'\.[^.]+$'), '');
        }
      });
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final link = _link.text.trim();
    if (title.length < 2) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    if (_file == null && link.isEmpty && _description.text.trim().isEmpty) {
      setState(() => _error = 'Attach a file, add a link or write some text.');
      return;
    }
    if (link.isNotEmpty &&
        !(Uri.tryParse(link)?.isScheme('https') ?? false) &&
        !(Uri.tryParse(link)?.isScheme('http') ?? false)) {
      setState(() => _error = 'Links must start with http:// or https://');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final classroom = ClassroomService();
    final draft = SharedResource(
      id: '',
      academyId: widget.classEntity.academyId,
      classId: widget.classEntity.id,
      teacherId: '',
      teacherName: '',
      title: title,
      description: _description.text,
      fileUrl: link.isEmpty ? null : link,
      contentText: _file == null && link.isEmpty ? _description.text : '',
      createdAt: DateTime.now(),
    );
    String? createdId;
    try {
      if (_file == null) {
        await classroom.uploadResource(draft);
      } else {
        createdId = await classroom.createResourceForAttachment(draft);
        await FileService().upload(
          category: FileCategory.courseMaterial,
          ownerId: createdId,
          filename: _file!.$1,
          bytes: _file!.$2,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Never leave an empty material behind when the upload failed.
      if (createdId != null) {
        try {
          await classroom.deleteResource(createdId);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share material',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            Text(widget.classEntity.displayLabel,
                style: TextStyle(color: colors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pick,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(_file == null
                  ? 'Choose file (PDF, Word, PowerPoint, image… max 4 MB)'
                  : _file!.$1),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.all(14),
                alignment: Alignment.centerLeft,
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
                label: 'Title',
                hint: 'e.g. Chapter 3 notes',
                controller: _title),
            LabeledField(
                label: 'Description (optional)',
                hint: 'What is this for?',
                controller: _description),
            LabeledField(
                label: 'Link (optional)', hint: 'https://…', controller: _link),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger)),
              ),
            PrimaryButton(
              label: 'Share with class',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
