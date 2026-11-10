import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../logic/auth_provider.dart';
import '../engine/ocr_engine.dart';
import '../models/ocr_capture.dart';
import '../services/document_picker.dart';
import '../services/ocr_capture_controller.dart';
import '../services/ocr_firestore_service.dart';

/// Unified OCR capture screen that works on web and mobile. Users pick PDFs or
/// images (or use the camera), extract text page by page, edit it, then save.
/// Built on the platform-abstracted OCR engine (ML Kit on mobile, Tesseract.js
/// on web) so Android and Web have the same capability.
class OcrCaptureScreen extends StatefulWidget {
  const OcrCaptureScreen({super.key});

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  final DocumentPicker _picker = DocumentPicker();
  final OcrCaptureController _ocr = OcrCaptureController();
  final OcrFirestoreService _store = OcrFirestoreService();
  final TextEditingController _text = TextEditingController();
  final TextEditingController _title = TextEditingController();

  final List<PickedDocument> _docs = [];
  OcrLanguage _language = OcrLanguage.english;
  bool _processing = false;
  bool _saving = false;
  int _done = 0;
  int _total = 0;
  String? _error;

  @override
  void dispose() {
    _ocr.dispose();
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  bool get _urduUnsupported =>
      _language != OcrLanguage.english && !_ocr.supports(OcrLanguage.urdu);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickFiles() async {
    try {
      final picked = await _picker.pickDocuments();
      if (picked.isEmpty) return;
      setState(() => _docs.addAll(picked));
    } catch (e) {
      _snack('Could not open files: $e');
    }
  }

  Future<void> _camera() async {
    try {
      final shot = await _picker.captureFromCamera();
      if (shot == null) return;
      setState(() => _docs.add(shot));
    } catch (e) {
      _snack('Camera is not available: $e');
    }
  }

  Future<void> _extract() async {
    if (_docs.isEmpty) return;
    setState(() {
      _processing = true;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      final result = await _ocr.run(
        _docs,
        language: _language,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
      if (!mounted) return;
      final combined = result.combinedText;
      setState(() {
        // Append so a second batch does not wipe edited text.
        _text.text = _text.text.trim().isEmpty
            ? combined
            : '${_text.text.trim()}\n\n$combined';
      });
      if (result.isEmpty) {
        _snack('No text was found. Try a clearer image or a different language.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'OCR failed: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      _snack('Extract or type some text before saving.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      _snack('Please enter a title.');
      return;
    }
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      _snack('You are not signed in.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _store.saveDocument(
        title: _title.text,
        extractedText: _text.text,
        createdByUid: user.uid,
        createdByName: user.fullName,
      );
      _snack('Document saved.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Document (OCR)')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sourceButtons(),
                const SizedBox(height: 12),
                _languageSelector(),
                if (_docs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _docChips(),
                ],
                const SizedBox(height: 12),
                _extractButton(),
                if (_processing && _total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                            value: _total == 0 ? null : _done / _total),
                        const SizedBox(height: 4),
                        Text('Reading page $_done of $_total…'),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                  ),
                const SizedBox(height: 20),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _text,
                  minLines: 6,
                  maxLines: 20,
                  decoration: const InputDecoration(
                    labelText: 'Extracted text (edit before saving)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save document'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _processing ? null : _pickFiles,
            icon: const Icon(Icons.upload_file),
            label: const Text('PDF / Image'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _processing ? null : _camera,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Camera'),
          ),
        ),
      ],
    );
  }

  Widget _languageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.translate, size: 20),
            const SizedBox(width: 8),
            const Text('Language:'),
            const SizedBox(width: 12),
            DropdownButton<OcrLanguage>(
              value: _language,
              onChanged: _processing
                  ? null
                  : (v) => setState(() => _language = v ?? OcrLanguage.english),
              items: OcrLanguage.values
                  .map((l) =>
                      DropdownMenuItem(value: l, child: Text(l.label)))
                  .toList(),
            ),
          ],
        ),
        if (_urduUnsupported)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              kIsWeb
                  ? 'Urdu recognition is available here.'
                  : 'Urdu is only supported on the web app; this device will read Latin text only.',
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _docChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _docs.length; i++)
          Chip(
            avatar: Icon(
              _docs[i].kind == OcrSourceKind.pdf
                  ? Icons.picture_as_pdf
                  : Icons.image_outlined,
              size: 18,
            ),
            label: Text(
              _docs[i].name.length > 24
                  ? '${_docs[i].name.substring(0, 22)}…'
                  : _docs[i].name,
            ),
            onDeleted: _processing ? null : () => setState(() => _docs.removeAt(i)),
          ),
      ],
    );
  }

  Widget _extractButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: (_docs.isEmpty || _processing) ? null : _extract,
        icon: _processing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.document_scanner_outlined),
        label: Text(_processing ? 'Extracting…' : 'Extract text'),
      ),
    );
  }
}
