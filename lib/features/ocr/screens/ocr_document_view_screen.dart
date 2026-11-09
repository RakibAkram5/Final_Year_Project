import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../models/ocr_document_model.dart';
import '../services/ocr_firestore_service.dart';
import '../services/ocr_publish_service.dart';

class OcrDocumentViewScreen extends StatefulWidget {
  final OcrDocumentModel document;

  const OcrDocumentViewScreen({super.key, required this.document});

  @override
  State<OcrDocumentViewScreen> createState() => _OcrDocumentViewScreenState();
}

class _OcrDocumentViewScreenState extends State<OcrDocumentViewScreen> {
  late TextEditingController _textController;
  late TextEditingController _titleController;
  final OcrFirestoreService _firestoreService = OcrFirestoreService();

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _textController =
        TextEditingController(text: widget.document.extractedText);
    _titleController = TextEditingController(text: widget.document.title);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) {
        context.read<ClassProvider>().listenAll(user.academyId ?? '');
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _updateDocument() async {
    if (_titleController.text.trim().isEmpty) {
      _showSnackBar("Title khali nahi ho sakta!", isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _firestoreService.updateDocument(
        documentId: widget.document.id,
        title: _titleController.text,
        extractedText: _textController.text,
      );

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      _showSnackBar("Document updated successfully!");
    } catch (e) {
      setState(() => _isSaving = false);
      _showSnackBar("Update failed: $e", isError: true);
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _textController.text));
    _showSnackBar("Text copied to clipboard!");
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
        title: Text(_isEditing ? "Edit Document" : "View Document",
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [_publishButton(), _editToggleButton()],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildTeacherNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: _isEditing ? "Edit Document" : "View Document",
      titleIcon: Icons.description_rounded,
      navSections: navSections,
      activeNavId: 'ocr_history',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_isEditing ? "Edit Document" : "View Document",
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800)),
                  ),
                  _publishButton(),
                  _editToggleButton(),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _publishButton() {
    return IconButton(
      icon: Icon(Icons.publish_rounded, color: context.appColors.accentText),
      tooltip: 'Publish to Resources',
      onPressed: () => publishOcrDocumentsToClass(context, [widget.document]),
    );
  }

  Widget _editToggleButton() {
    return !_isEditing
        ? IconButton(
            icon: Icon(Icons.edit_rounded, color: context.appColors.accentText),
            onPressed: () => setState(() => _isEditing = true),
          )
        : IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.danger),
            onPressed: () {
              setState(() {
                _isEditing = false;
                _titleController.text = widget.document.title;
                _textController.text = widget.document.extractedText;
              });
            },
          );
  }

  Widget _body() {
    final dateStr =
        DateFormat('MMMM d, yyyy • h:mm a').format(widget.document.createdAt);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Info
                if (!_isEditing) ...[
                  Text(
                    widget.document.title,
                    style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Scanned on $dateStr",
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "By ${widget.document.createdByName}",
                    style: TextStyle(
                        color: context.appColors.accentText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ] else ...[
                  Text(
                    "DOCUMENT TITLE",
                    style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: "Enter title...",
                      filled: true,
                      fillColor: context.appColors.inputFill,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Divider(color: context.appColors.border, thickness: 1),
                const SizedBox(height: 24),

                // Extracted Text
                Text(
                  "EXTRACTED CONTENT",
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.appColors.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: context.appColors.border.withValues(alpha: 0.5)),
                  ),
                  child: TextField(
                    controller: _textController,
                    enabled: _isEditing,
                    maxLines: null,
                    style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "No text content",
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),

        // Bottom Actions
        Padding(
          padding: const EdgeInsets.all(20),
          child: _isEditing
              ? PrimaryButton(
                  label: "SAVE CHANGES",
                  onPressed: _updateDocument,
                  loading: _isSaving,
                  icon: Icons.check_circle_rounded,
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyToClipboard,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text("COPY ALL"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.appColors.textSecondary,
                          side: BorderSide(color: context.appColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
