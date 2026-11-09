import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/theme_extensions.dart';
import '../data/remote/file_service.dart';
import '../features/shared/file_viewer_screen.dart';
import 'responsive/responsive_action_tile.dart';

/// Picks a file allowed for [category], enforcing the 4 MB limit.
/// Returns (name, bytes) or null if cancelled; shows a snackbar on errors.
Future<(String, Uint8List)?> pickFileFor(
    BuildContext context, FileCategory category) async {
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: category.allowedExtensions,
    );
    if (picked.isEmpty) return null;
    final file = picked.first;
    final size = await file.length();
    if (size != null && size > FileService.maxUploadBytes) {
      throw StateError('Files must be 4 MB or smaller.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > FileService.maxUploadBytes) {
      throw StateError('Files must be 4 MB or smaller.');
    }
    return (file.name, bytes);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e is StateError ? e.message : 'Could not open file: $e'),
          backgroundColor: AppColors.danger));
    }
    return null;
  }
}

IconData fileIconFor(StoredFile f) {
  if (f.isPdf) return Icons.picture_as_pdf_rounded;
  if (f.isImage) return Icons.image_rounded;
  if (f.mimeType.contains('word')) return Icons.description_rounded;
  if (f.mimeType.contains('sheet') || f.mimeType.contains('excel')) {
    return Icons.table_chart_rounded;
  }
  if (f.mimeType.contains('presentation') ||
      f.mimeType.contains('powerpoint')) {
    return Icons.slideshow_rounded;
  }
  return Icons.insert_drive_file_rounded;
}

/// Lists the files attached to one record (a course material, assignment,
/// submission, student or teacher) with preview/download, and — when
/// [canEdit] — upload, replace and delete. Loading, empty and error states
/// are handled here so every screen behaves the same.
class AttachmentsSection extends StatefulWidget {
  final FileCategory category;
  final String ownerId;
  final bool canEdit;
  final String title;
  final String emptyText;
  final int? maxFiles;
  final FileService? service;

  const AttachmentsSection({
    super.key,
    required this.category,
    required this.ownerId,
    this.canEdit = false,
    this.title = 'Files',
    this.emptyText = 'No files yet.',
    this.maxFiles,
    this.service,
  });

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  late FileService _service;
  late Stream<List<StoredFile>> _stream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FileService();
    _stream = _service.watch(widget.category, widget.ownerId);
  }

  @override
  void didUpdateWidget(covariant AttachmentsSection old) {
    super.didUpdateWidget(old);
    if (old.ownerId != widget.ownerId || old.category != widget.category) {
      _stream = _service.watch(widget.category, widget.ownerId);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : AppColors.success));
  }

  Future<void> _run(Future<void> Function() op, String success) async {
    if (_busy) return; // prevents duplicate submissions
    setState(() => _busy = true);
    try {
      await op();
      _toast(success);
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final picked = await pickFileFor(context, widget.category);
    if (picked == null) return;
    await _run(
        () => _service.upload(
            category: widget.category,
            ownerId: widget.ownerId,
            filename: picked.$1,
            bytes: picked.$2),
        '"${picked.$1}" uploaded');
  }

  Future<void> _replace(StoredFile f) async {
    final picked = await pickFileFor(context, widget.category);
    if (picked == null) return;
    await _run(() => _service.replace(f, filename: picked.$1, bytes: picked.$2),
        '"${f.originalName}" replaced');
  }

  Future<void> _delete(StoredFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('"${f.originalName}" will be permanently removed.'),
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
    if (ok == true) await _run(() => _service.delete(f), 'File deleted');
  }

  void _open(StoredFile f) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FileViewerScreen(file: f, service: _service)));

  Future<void> _download(StoredFile f) => _run(() async {
        final bytes = await _service.download(f);
        if (!mounted) return;
        await saveOrShareBytes(context, bytes, f.originalName, f.mimeType);
      }, 'Ready: ${f.originalName}');

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return StreamBuilder<List<StoredFile>>(
      stream: _stream,
      builder: (context, snap) {
        final files = snap.data ?? const <StoredFile>[];
        final canAdd = widget.canEdit &&
            (widget.maxFiles == null || files.length < widget.maxFiles!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(widget.title.toUpperCase(),
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1)),
              ),
              if (_busy)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent))
              else if (canAdd)
                TextButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Upload'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.accent),
                ),
            ]),
            const SizedBox(height: 6),
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent)),
              )
            else if (snap.hasError && files.isEmpty)
              Text('Could not load files: ${snap.error}',
                  style: const TextStyle(color: AppColors.danger, fontSize: 12))
            else if (files.isEmpty)
              Text(widget.emptyText,
                  style: TextStyle(color: colors.textMuted, fontSize: 12))
            else
              for (final f in files)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ResponsiveActionTile(
                    key: ValueKey(f.id),
                    onTap: () => _open(f),
                    leading: Icon(fileIconFor(f),
                        color: context.appColors.accentText),
                    title: f.originalName,
                    titleStyle: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    subtitles: [
                      Text(
                          '${f.sizeLabel} · ${DateFormat('d MMM yyyy').format(f.createdAt)}'
                          '${f.uploadedByName == null ? '' : ' · ${f.uploadedByName}'}',
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 12)),
                    ],
                    actions: [
                      TileAction(
                          icon: Icons.visibility_rounded,
                          label: 'Preview',
                          onPressed: () => _open(f)),
                      TileAction(
                          icon: Icons.download_rounded,
                          label: 'Download',
                          onPressed: _busy ? null : () => _download(f)),
                      if (widget.canEdit) ...[
                        TileAction(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Replace',
                            onPressed: _busy ? null : () => _replace(f)),
                        TileAction(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            destructive: true,
                            onPressed: _busy ? null : () => _delete(f)),
                      ],
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}
