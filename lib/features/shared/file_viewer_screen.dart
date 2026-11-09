import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/remote/file_service.dart';
import '../../widgets/gradient_background.dart';

/// Saves or shares bytes: the system share sheet on mobile, a browser
/// download on web (share_plus falls back to downloading).
Future<void> saveOrShareBytes(BuildContext context, Uint8List bytes,
    String filename, String mimeType) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
    fileNameOverrides: [filename],
    sharePositionOrigin:
        box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}

/// Downloads a stored file through the authenticated API and previews it:
/// PDFs with page scrolling + pinch/double-tap zoom, images with pan/zoom,
/// other formats with a download/share action.
class FileViewerScreen extends StatefulWidget {
  final StoredFile file;
  final FileService? service;
  const FileViewerScreen({super.key, required this.file, this.service});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  late Future<Uint8List> _bytes;

  FileService get _service => widget.service ?? FileService();

  @override
  void initState() {
    super.initState();
    _bytes = _service.download(widget.file);
  }

  void _retry() => setState(() => _bytes = _service.download(widget.file));

  Future<void> _share(Uint8List bytes) async {
    try {
      await saveOrShareBytes(
          context, bytes, widget.file.originalName, widget.file.mimeType);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save the file: $e'),
          backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(f.originalName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snap) => IconButton(
              tooltip: 'Download / share',
              icon: Icon(Icons.download_rounded,
                  color: context.appColors.accentText),
              onPressed: snap.hasData ? () => _share(snap.data!) : null,
            ),
          ),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: AppColors.accent),
                  SizedBox(height: 12),
                  Text('Loading file…'),
                ]));
              }
              if (snap.hasError) {
                return _message(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.danger,
                  text: 'Could not load this file.\n${snap.error}',
                  action: OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry')),
                );
              }
              final bytes = snap.data!;
              if (f.isPdf) {
                return PdfPreview(
                  build: (_) async => bytes,
                  pdfFileName: f.originalName,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  // Lower raster density keeps memory reasonable for long
                  // documents; zooming re-renders at higher resolution.
                  dpi: 150,
                  maxPageWidth: 900,
                  loadingWidget:
                      const CircularProgressIndicator(color: AppColors.accent),
                  onError: (_, error) => _message(
                      icon: Icons.picture_as_pdf_rounded,
                      color: AppColors.danger,
                      text: 'This PDF could not be displayed: $error'),
                );
              }
              if (f.isImage) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(bytes,
                        errorBuilder: (_, __, ___) => _message(
                            icon: Icons.broken_image_rounded,
                            color: AppColors.danger,
                            text: 'This image could not be displayed.')),
                  ),
                );
              }
              return _message(
                icon: Icons.insert_drive_file_rounded,
                color: AppColors.accent,
                text: '${f.originalName}\n${f.sizeLabel}\n\n'
                    'Preview is not available for this file type. '
                    'Download it to open it in another app.',
                action: FilledButton.icon(
                  onPressed: () => _share(bytes),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download / share'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textOnAccent),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _message(
      {required IconData icon,
      required Color color,
      required String text,
      Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textSecondary)),
          if (action != null) ...[const SizedBox(height: 16), action],
        ]),
      ),
    );
  }
}
