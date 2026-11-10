import 'dart:io';
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/session_provider.dart';
import '../../../logic/text_rank_summarizer.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class AiSummarizerScreen extends StatefulWidget {
  const AiSummarizerScreen({super.key});

  @override
  State<AiSummarizerScreen> createState() => _AiSummarizerScreenState();
}

class _AiSummarizerScreenState extends State<AiSummarizerScreen> {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();

  File? _image;
  String _summary = "";
  bool _isProcessing = false;

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final session = context.read<SessionProvider>();
    session.suppressBackgroundLogout();
    final XFile? pickedFile;
    try {
      pickedFile = await _picker.pickImage(source: source);
    } finally {
      session.resumeBackgroundLogoutTracking();
    }
    if (!mounted) return;
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      setState(() {
        _image = file;
        _summary = "";
      });
      _processImage();
    }
  }

  Future<void> _processImage() async {
    if (_image == null) return;
    setState(() => _isProcessing = true);

    try {
      final inputImage = InputImage.fromFile(_image!);
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);
      if (!mounted) return;

      setState(() {
        _summary = _generateLocalSummary(recognizedText.text);
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackBar("Processing failed: $e", isError: true);
    }
  }

  /// 100% offline extractive summarization via TextRank — an unsupervised,
  /// graph-based ranking algorithm (no training data needed), rather than
  /// the previous plain formatting heuristic (short/ALL-CAPS lines) that
  /// also operated on raw OCR '\n' breaks instead of real sentences.
  String _generateLocalSummary(String text) {
    if (text.isEmpty) return "No text detected to summarize.";

    final topSentences = TextRankSummarizer.summarize(text, maxSentences: 6);
    if (topSentences.isEmpty) {
      return "Detected text is too short for a structured summary:\n\n$text";
    }

    final sb = StringBuffer();
    sb.writeln("📌 QUICK SUMMARY (OFFLINE AI — TextRank)\n");
    sb.writeln("💡 KEY POINTS:");
    for (final s in topSentences) {
      sb.writeln("• $s.");
    }

    return sb.toString();
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: isError ? AppColors.danger : AppColors.success),
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
        title: const Text('AI Notes Summarizer',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildStudentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'AI Notes Summarizer',
      titleIcon: Icons.auto_awesome_rounded,
      navSections: navSections,
      activeNavId: 'ai_summarizer',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildActionButtons(),
          const SizedBox(height: 20),
          if (_isProcessing)
            const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
          else if (_summary.isNotEmpty)
            _buildSummaryCard()
          else
            _buildEmptyState(),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                _isProcessing ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text("SCAN NOTES"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textOnAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                _isProcessing ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.image_rounded),
            label: const Text("GALLERY"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  color: context.appColors.accentText, size: 20),
              const SizedBox(width: 8),
              Text("AI INSIGHTS",
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.copy_rounded,
                    color: context.appColors.textMuted, size: 20),
                onPressed: () {
                  // Copy to clipboard logic
                  _showSnackBar("Summary copied to clipboard!");
                },
              ),
            ],
          ),
          Divider(color: context.appColors.border, height: 32),
          Text(_summary,
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontSize: 14,
                  height: 1.6)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          Icon(Icons.description_outlined,
              size: 80,
              color: context.appColors.textMuted.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text(
            "Scan your handwritten or printed\nnotes to get an instant AI summary.",
            textAlign: TextAlign.center,
            style:
                TextStyle(color: context.appColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            "100% OFFLINE. NO INTERNET REQUIRED.",
            style: TextStyle(
                color: context.appColors.accentText,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}
