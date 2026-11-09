import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../models/ocr_document_model.dart';
import '../services/ocr_firestore_service.dart';
import '../services/ocr_publish_service.dart';
import 'ocr_document_view_screen.dart';

class OcrHistoryScreen extends StatefulWidget {
  const OcrHistoryScreen({super.key});

  @override
  State<OcrHistoryScreen> createState() => _OcrHistoryScreenState();
}

class _OcrHistoryScreenState extends State<OcrHistoryScreen> {
  final _firestoreService = OcrFirestoreService();
  final Set<String> _selectedIds = {};

  bool get _selecting => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) {
        context.read<ClassProvider>().listenAll(user.academyId ?? '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _selecting ? '${_selectedIds.length} selected' : "OCR History",
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selectedIds.clear()),
                ),
              ]
            : null,
      ),
      body: GradientBackground(
        child: _body(context, user),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final navSections = buildTeacherNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'OCR History',
      titleIcon: Icons.history_rounded,
      navSections: navSections,
      activeNavId: 'ocr_history',
      user: user,
      onLogout: () => performWebLogout(context),
      body: _body(context, user),
    );
  }

  Widget _body(BuildContext context, dynamic user) {
    if (user == null) {
      return Center(
          child: Text("Please login to view history",
              style: TextStyle(color: context.appColors.textSecondary)));
    }
    return StreamBuilder<List<OcrDocumentModel>>(
      stream: _firestoreService.getDocuments(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                "Error loading history: ${snapshot.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          );
        }

        final docs = snapshot.data ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_rounded,
                    size: 64,
                    color: context.appColors.textMuted.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text(
                  "No scanned documents yet.",
                  style: TextStyle(
                      color: context.appColors.textSecondary, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _documentTile(context, docs[index]),
              ),
            ),
            if (_selecting) _publishBar(context, docs),
          ],
        );
      },
    );
  }

  Widget _publishBar(BuildContext context, List<OcrDocumentModel> allDocs) {
    final selected = allDocs.where((d) => _selectedIds.contains(d.id)).toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: () async {
            await publishOcrDocumentsToClass(context, selected);
            if (mounted) setState(() => _selectedIds.clear());
          },
          icon: const Icon(Icons.publish_rounded, size: 18),
          label: Text('Publish ${selected.length} to Resources'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.textOnAccent,
            minimumSize: const Size(double.infinity, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _documentTile(BuildContext context, OcrDocumentModel doc) {
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(doc.createdAt);
    final selected = _selectedIds.contains(doc.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (_selecting) {
            setState(() {
              if (selected) {
                _selectedIds.remove(doc.id);
              } else {
                _selectedIds.add(doc.id);
              }
            });
          } else {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => OcrDocumentViewScreen(document: doc)));
          }
        },
        onLongPress: () => setState(() => _selectedIds.add(doc.id)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.1)
                : context.appColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected
                    ? AppColors.accent
                    : context.appColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? context.appColors.accentText
                          : context.appColors.textMuted),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.description_rounded,
                      color: context.appColors.accentText, size: 24),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                          color: context.appColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      doc.extractedText,
                      style: TextStyle(
                          color: context.appColors.textSecondary, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!_selecting)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 20),
                  onPressed: () => _confirmDelete(context, doc),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, OcrDocumentModel doc) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: Text("Delete Document?",
            style: TextStyle(color: context.appColors.textPrimary)),
        content: Text("Are you sure you want to delete '${doc.title}'?",
            style: TextStyle(color: context.appColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("CANCEL",
                style: TextStyle(color: context.appColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("DELETE",
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestoreService.deleteDocument(doc.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Document deleted successfully"),
                behavior: SnackBarBehavior.floating),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("Delete failed: $e"),
                backgroundColor: AppColors.danger,
                behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }
}
