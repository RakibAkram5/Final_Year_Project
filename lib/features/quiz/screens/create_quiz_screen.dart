import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../logic/session_provider.dart';
import '../../../logic/text_rank_summarizer.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/quiz_model.dart';

class CreateQuizScreen extends StatefulWidget {
  final String classId;
  final bool isAiGen;
  const CreateQuizScreen(
      {super.key, required this.classId, this.isAiGen = false});

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _chapterCtrl = TextEditingController();
  final _sessionCtrl = TextEditingController(text: 'Monthly Test');

  String _selectedMonth = DateFormat('MMMM').format(DateTime.now());
  String _difficulty = 'Medium';
  final DateTime _testDate = DateTime.now();

  // Online attempt settings. Off by default: a test is a printed paper unless
  // the teacher explicitly opens it for attempts in the student portal.
  bool _online = false;
  final _durationCtrl = TextEditingController();
  DateTime? _availableUntil;

  final List<QuizQuestion> _questions = [];

  /// MCQ -> Short -> Long, preserving relative order within each type —
  /// makes "Q1 is always MCQ" a structural guarantee (whenever at least one
  /// MCQ exists) instead of incidental insertion order, and fixes manually
  /// added questions previously always appending to the end regardless of
  /// type. Used for both the on-screen list and what actually gets saved.
  List<QuizQuestion> get _sortedQuestions => [
        ..._questions.where((q) => q.type == QuestionType.mcq),
        ..._questions.where((q) => q.type == QuestionType.short),
        ..._questions.where((q) => q.type == QuestionType.long),
      ];

  double get _totalMarks => _questions.fold(0.0, (sum, q) => sum + q.marks);

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  bool _isAnalyzing = false;
  // Full OCR text, kept separately from the truncated preview shown in the
  // dialog so question generation always runs on the complete scanned
  // content, not just the first 100 characters used for display.
  String _scannedText = '';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    _instructionsCtrl.dispose();
    _durationCtrl.dispose();
    _chapterCtrl.dispose();
    _sessionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImageAndAnalyze() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.appColors.surface,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.camera_alt_rounded,
                color: context.appColors.accentText),
            title: Text("Camera",
                style: TextStyle(color: context.appColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading:
                Icon(Icons.image_rounded, color: context.appColors.accentText),
            title: Text("Gallery",
                style: TextStyle(color: context.appColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    );

    if (source == null) return;
    if (!mounted) return;

    final session = context.read<SessionProvider>();
    session.suppressBackgroundLogout();
    final XFile? pickedFile;
    try {
      pickedFile = await picker.pickImage(source: source);
    } finally {
      session.resumeBackgroundLogoutTracking();
    }
    if (pickedFile == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final inputImage = InputImage.fromFile(File(pickedFile.path));
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      if (recognizedText.text.trim().isEmpty) {
        throw Exception("No text detected in the image!");
      }

      _analyzeContentAndShowRecommendations(recognizedText.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("AI Analysis Failed: $e"),
              backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _analyzeContentAndShowRecommendations(String text) {
    _scannedText = text;
    // Offline AI Heuristic Logic
    final lines = text.split('\n').where((l) => l.trim().length > 10).toList();
    final wordCount = text.split(' ').length;

    // 1. Difficulty prediction based on average word length and complex markers
    String predictedDifficulty = "Medium";
    if (wordCount < 100) predictedDifficulty = "Easy";
    if (text.contains('law') ||
        text.contains('theorem') ||
        text.contains('equation') ||
        wordCount > 500) {
      predictedDifficulty = "Hard";
    }

    // 2. Question counts based on content density
    int mcqs = (wordCount / 40).clamp(3, 15).toInt();
    int sqs = (lines.length / 4).clamp(2, 10).toInt();
    int lqs = (wordCount > 300) ? 2 : 1;

    _showAiRecommendationsDialog(predictedDifficulty, mcqs, sqs, lqs,
        text.substring(0, text.length > 100 ? 100 : text.length));
  }

  void _showAiRecommendationsDialog(
      String diff, int mcqs, int sqs, int lqs, String preview) {
    final mcqCountCtrl = TextEditingController(text: mcqs.toString());
    final sqCountCtrl = TextEditingController(text: sqs.toString());
    final lqCountCtrl = TextEditingController(text: lqs.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: Row(
          children: [
            Icon(Icons.auto_awesome,
                color: context.appColors.accentText, size: 20),
            const SizedBox(width: 10),
            Text("AI Test Blueprint",
                style: TextStyle(color: context.appColors.textPrimary)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Topic: $preview...",
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),
              _aiStatRow("Predicted Difficulty", diff, AppColors.accent),
              Divider(color: context.appColors.border, height: 24),
              Text("ADJUST QUESTION COUNTS:",
                  style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 12),
              _countInput("MCQs", mcqCountCtrl),
              _countInput("Short Questions", sqCountCtrl),
              _countInput("Long Questions", lqCountCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("CANCEL",
                style: TextStyle(color: context.appColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textOnAccent),
            onPressed: () {
              final mCount = int.tryParse(mcqCountCtrl.text) ?? mcqs;
              final sCount = int.tryParse(sqCountCtrl.text) ?? sqs;
              final lCount = int.tryParse(lqCountCtrl.text) ?? lqs;

              final actual = _generateQuestionsLocally(
                  _scannedText, diff, mCount, sCount, lCount);

              setState(() {
                _difficulty = diff;
                _instructionsCtrl.text =
                    "Attempt all ${actual.mcq} MCQs, ${actual.sq} Short Questions and ${actual.lq} Long Questions.";
              });
              Navigator.pop(ctx);
            },
            child: const Text("GENERATE & APPLY"),
          ),
        ],
      ),
    );
  }

  Widget _countInput(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: context.appColors.textPrimary, fontSize: 13))),
          SizedBox(
            width: 60,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                fillColor: context.appColors.inputFill,
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Common words that carry no grading signal on their own — excluded so
  // the AI Smart Grader's keyword match only counts topic-bearing words.
  static const _stopWords = {
    'the',
    'a',
    'an',
    'and',
    'or',
    'but',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'being',
    'to',
    'of',
    'in',
    'on',
    'at',
    'by',
    'for',
    'with',
    'about',
    'as',
    'into',
    'through',
    'this',
    'that',
    'these',
    'those',
    'it',
    'its',
    'their',
    'his',
    'her',
    'they',
    'them',
    'which',
    'who',
    'whom',
    'refers',
    'also',
    'can',
    'may',
    'not',
    'from',
    'such',
    'than',
    'then',
    'so',
    'if',
    'when',
    'while',
    'has',
    'have',
    'had',
    'will',
  };

  /// Pulls topic words out of a source sentence so auto-generated Short/Long
  /// questions still carry `gradingKeywords` — otherwise the AI Smart Grader
  /// (which scores purely by keyword match) has nothing to check answers
  /// against and every auto-generated question silently grades as 0.
  List<String> _extractKeywords(String sentence, {int max = 6}) {
    final words = sentence
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 3 && !_stopWords.contains(w))
        .toSet() // de-duplicate
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // longest = most specific
    return words.take(max).toList();
  }

  ({int mcq, int sq, int lq}) _generateQuestionsLocally(
      String extractedText, String diff, int mcqs, int sqs, int lqs) {
    // 100% Offline Question Generation, sentence selection driven by
    // TextRank (the same unsupervised graph-ranking algorithm the AI
    // Summarizer uses) instead of arbitrary sentence length/position — the
    // most central ideas in the notes get first claim on each question
    // type, rather than whichever sentence happened to be longest.
    final rankedSentences = TextRankSummarizer.rankSentences(extractedText)
        .map((s) => s.replaceAll(RegExp(r'[.?!]+$'), '').trim())
        .where((s) => s.length > 15)
        .toList();

    final List<QuizQuestion> generated = [];
    final usedSentences = <String>{};

    // Heuristic 1: MCQs from "X is/refers to Y" definitions, highest
    // TextRank importance first.
    int mGenerated = 0;
    for (var sentence in rankedSentences) {
      if (mGenerated >= mcqs) break;
      if (usedSentences.contains(sentence)) continue;
      if (sentence.contains(' is ') || sentence.contains(' refers to ')) {
        final parts = sentence.split(RegExp(r' is | refers to '));
        if (parts.length == 2 &&
            parts[0].trim().isNotEmpty &&
            parts[1].trim().isNotEmpty) {
          generated.add(QuizQuestion(
            id: const Uuid().v4(),
            text:
                "What ${sentence.contains(' refers to ') ? 'refers to' : 'is'} ${parts[1].trim()}?",
            type: QuestionType.mcq,
            options: [
              parts[0].trim(),
              "None of the above",
              "Both A and B",
              "Incorrect definition"
            ],
            correctIndex: 0,
            marks: 1.0,
          ));
          usedSentences.add(sentence);
          mGenerated++;
        }
      }
    }

    // Remaining sentences, still in TextRank importance order.
    final remaining =
        rankedSentences.where((s) => !usedSentences.contains(s)).toList();

    // Heuristic 2: Long Questions from the most important remaining
    // sentences substantial enough to "discuss in detail".
    int lGenerated = 0;
    for (var sentence in remaining) {
      if (lGenerated >= lqs) break;
      if (usedSentences.contains(sentence)) continue;
      if (sentence.length < 80) continue;
      final preview =
          sentence.length > 60 ? '${sentence.substring(0, 60)}...' : sentence;
      generated.add(QuizQuestion(
        id: const Uuid().v4(),
        text: "Discuss in detail the following concept: $preview",
        type: QuestionType.long,
        marks: 8.0,
        gradingKeywords: _extractKeywords(sentence),
      ));
      usedSentences.add(sentence);
      lGenerated++;
    }

    // Heuristic 3: Short Questions from the next-most-important remaining
    // sentences.
    int sGenerated = 0;
    for (var sentence in remaining) {
      if (sGenerated >= sqs) break;
      if (usedSentences.contains(sentence)) continue;
      if (sentence.contains('?')) continue;
      generated.add(QuizQuestion(
        id: const Uuid().v4(),
        text: "Briefly explain: $sentence",
        type: QuestionType.short,
        marks: 2.0,
        gradingKeywords: _extractKeywords(sentence),
      ));
      usedSentences.add(sentence);
      sGenerated++;
    }

    setState(() {
      _questions.addAll(generated);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text("Generated ${generated.length} questions from notes!"),
          backgroundColor: AppColors.success),
    );

    return (mcq: mGenerated, sq: sGenerated, lq: lGenerated);
  }

  Widget _aiStatRow(String label, String value, Color valColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: context.appColors.textSecondary, fontSize: 13))),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  color: valColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  void _addQuestion() {
    // ... same as before
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _AddQuestionSheet(onAdd: (q) => setState(() => _questions.add(q))),
    );
  }

  Future<void> _saveQuiz() async {
    if (!_formKey.currentState!.validate()) return;
    if (_online && _durationCtrl.text.trim().isNotEmpty) {
      final d = int.tryParse(_durationCtrl.text.trim());
      if (d == null || d < 1 || d > 600) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Time limit must be between 1 and 600 minutes.')));
        return;
      }
    }
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one question!')));
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cp = Provider.of<ClassProvider>(context, listen: false);

    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Session expired. Please log in again.')));
      return;
    }

    final classMatches =
        cp.classes.where((c) => c.id == widget.classId).toList();
    if (classMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This class no longer exists.')));
      return;
    }
    final cls = classMatches.first;

    final quiz = QuizModel(
      id: const Uuid().v4(),
      academyId: user.academyId ?? '',
      classId: widget.classId,
      classLabel: "${cls.className} (${cls.section})",
      title: _titleCtrl.text.trim(),
      subject: _subjectCtrl.text.trim(),
      month: _selectedMonth,
      session: _sessionCtrl.text.trim(),
      chapter: _chapterCtrl.text.trim(),
      difficulty: _difficulty,
      totalMarks: _totalMarks,
      testDate: _testDate,
      instructions: _instructionsCtrl.text.trim(),
      createdByUid: user.uid,
      createdByName: user.fullName,
      createdAt: DateTime.now(),
      questions: _sortedQuestions,
      attemptMode: _online ? 'ONLINE' : 'PAPER',
      durationMinutes: _online ? int.tryParse(_durationCtrl.text.trim()) : null,
      availableUntil: _online ? _availableUntil : null,
    );

    try {
      await context.read<QuizProvider>().createQuiz(quiz);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Test created successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to create test: $e'),
            backgroundColor: AppColors.danger));
      }
    }
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
        title: Text(widget.isAiGen ? 'AI Test Generator' : 'Create Test',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(context),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildTeacherNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: widget.isAiGen ? 'AI Test Generator' : 'Create Test',
      titleIcon: Icons.auto_awesome_motion_rounded,
      navSections: navSections,
      activeNavId: widget.isAiGen ? 'ai_test_gen' : 'grading',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.isAiGen) ...[
            _buildAiScanButton(),
            const SizedBox(height: 24),
          ],
          _buildFormSection('TEST BASICS', [
            LabeledField(
                label: 'Test Title',
                hint: 'e.g. Unit 1 Quiz',
                controller: _titleCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Title is required'
                    : null),
            LabeledField(
                label: 'Subject',
                hint: 'e.g. Physics',
                controller: _subjectCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Subject is required'
                    : null),
          ]),
          _buildFormSection('ACADEMY DETAILS', [
            _buildDropdownField('Month', _selectedMonth, _months,
                (v) => setState(() => _selectedMonth = v!)),
            const SizedBox(height: 16),
            LabeledField(
                label: 'Test Session',
                hint: 'e.g. Annual 2024',
                controller: _sessionCtrl),
            LabeledField(
                label: 'Chapter / Topic',
                hint: 'e.g. Kinematics',
                controller: _chapterCtrl),
          ]),
          _buildFormSection('SPECIFICATIONS', [
            _buildDropdownField(
                'Difficulty',
                _difficulty,
                ['Easy', 'Medium', 'Hard'],
                (v) => setState(() => _difficulty = v!)),
            const SizedBox(height: 16),
            _totalMarksDisplay(),
            LabeledField(
                label: 'Instructions',
                hint: 'e.g. No calculators',
                controller: _instructionsCtrl),
          ]),
          _buildFormSection('ONLINE ATTEMPT', [_buildOnlineSettings()]),
          const SizedBox(height: 10),
          Text('QUESTIONS',
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          ..._buildQuestionSections(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addQuestion,
            icon: Icon(Icons.add_circle_outline,
                color: context.appColors.accentText),
            label: Text('Add Question',
                style: TextStyle(color: context.appColors.accentText)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: context.appColors.border),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'Save & Publish Test',
            icon: Icons.cloud_upload_rounded,
            loading: context.watch<QuizProvider>().loading,
            onPressed: context.watch<QuizProvider>().loading ? null : _saveQuiz,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildAiScanButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  color: context.appColors.accentText, size: 20),
              const SizedBox(width: 10),
              Text("AI TEST ASSISTANT",
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
              "Take a photo of the textbook topic — TextRank ranks the most important sentences to build your questions from, offline.",
              style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                  height: 1.4)),
          const SizedBox(height: 16),
          PrimaryButton(
            label: "SCAN TOPIC WITH AI",
            icon: Icons.camera_enhance_rounded,
            loading: _isAnalyzing,
            onPressed: _pickImageAndAnalyze,
          ),
        ],
      ),
    );
  }

  /// Lets the teacher open this test for attempts in the student portal.
  /// MCQs are then graded automatically on submission; written answers are
  /// reviewed in "Submissions". Paper tests are unaffected.
  Widget _buildOnlineSettings() {
    final df = DateFormat('d MMM yyyy, h:mm a');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _online,
            activeThumbColor: AppColors.accent,
            title: Text('Students attempt this test online',
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(
                _online
                    ? 'Multiple-choice answers are graded automatically; you grade written answers in Submissions.'
                    : 'Off: this is a printed paper sat in class. Marks are entered manually.',
                style: TextStyle(
                    color: context.appColors.textMuted, fontSize: 12)),
            onChanged: (v) => setState(() => _online = v),
          ),
          if (_online) ...[
            const SizedBox(height: 8),
            LabeledField(
                label: 'Time limit (minutes, optional)',
                hint: 'e.g. 30 — leave empty for no limit',
                keyboardType: TextInputType.number,
                controller: _durationCtrl),
            Text('Deadline (optional)',
                style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDeadline,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                        _availableUntil == null
                            ? 'No deadline — open until you delete the test'
                            : 'Closes ${df.format(_availableUntil!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                if (_availableUntil != null)
                  IconButton(
                    tooltip: 'Remove deadline',
                    onPressed: () => setState(() => _availableUntil = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _availableUntil ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 23, minute: 59);
    setState(() => _availableUntil =
        DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  Widget _buildFormSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: context.appColors.accentText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
        const SizedBox(height: 16),
        ...children,
        const SizedBox(height: 12),
      ],
    );
  }

  /// Read-only — recomputed live from `_questions` on every add/delete/
  /// generate instead of a manually-typed field that could drift out of
  /// sync with the actual question marks.
  Widget _totalMarksDisplay() {
    final formatted = _totalMarks == _totalMarks.roundToDouble()
        ? _totalMarks.toInt().toString()
        : _totalMarks.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total Marks',
            style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.appColors.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.appColors.border),
          ),
          child: Text(
              _questions.isEmpty
                  ? '$formatted (add questions below)'
                  : formatted,
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> items,
      ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.appColors.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.appColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items
                  .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m,
                          style:
                              TextStyle(color: context.appColors.textPrimary))))
                  .toList(),
              onChanged: onChanged,
              dropdownColor: context.appColors.surface,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down,
                  color: context.appColors.accentText),
            ),
          ),
        ),
      ],
    );
  }

  /// MCQ / Short / Long, each under its own header, numbered continuously
  /// across sections — mirrors the PDF's section grouping so what the
  /// teacher previews here matches what gets printed.
  List<Widget> _buildQuestionSections() {
    final sorted = _sortedQuestions;
    final widgets = <Widget>[];
    String? lastHeader;
    for (var i = 0; i < sorted.length; i++) {
      final q = sorted[i];
      final header = switch (q.type) {
        QuestionType.mcq => 'Multiple Choice Questions',
        QuestionType.short => 'Short Questions',
        QuestionType.long => 'Long Questions',
      };
      if (header != lastHeader) {
        if (lastHeader != null) widgets.add(const SizedBox(height: 4));
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(header,
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ));
        lastHeader = header;
      }
      widgets.add(_questionCard(i + 1, q));
    }
    return widgets;
  }

  Widget _questionCard(int index, QuizQuestion q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.accent,
                child: Text('$index',
                    style: const TextStyle(
                        color: AppColors.textOnAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Text(
                  switch (q.type) {
                    QuestionType.mcq => 'MCQ',
                    QuestionType.long => 'Long Answer',
                    QuestionType.short => 'Short Answer',
                  },
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 18),
                onPressed: () => setState(() => _questions.remove(q)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(q.text,
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AddQuestionSheet extends StatefulWidget {
  final Function(QuizQuestion) onAdd;
  const _AddQuestionSheet({required this.onAdd});

  @override
  State<_AddQuestionSheet> createState() => _AddQuestionSheetState();
}

class _AddQuestionSheetState extends State<_AddQuestionSheet> {
  final _questionCtrl = TextEditingController();
  final _marksCtrl = TextEditingController(text: '1');
  final _keywordsCtrl = TextEditingController();
  QuestionType _type = QuestionType.mcq;

  final List<TextEditingController> _optionCtrls =
      List.generate(4, (_) => TextEditingController());
  int _correctIdx = 0;

  @override
  void dispose() {
    _questionCtrl.dispose();
    _marksCtrl.dispose();
    _keywordsCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Question',
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            Row(
              children: [
                _typeBtn('MCQ', QuestionType.mcq),
                const SizedBox(width: 12),
                _typeBtn('Short Answer', QuestionType.short),
                const SizedBox(width: 12),
                _typeBtn('Long Answer', QuestionType.long),
              ],
            ),
            const SizedBox(height: 20),
            LabeledField(
                label: 'Question Text',
                hint: 'Enter question',
                controller: _questionCtrl),
            LabeledField(
                label: 'Marks',
                hint: '1',
                controller: _marksCtrl,
                keyboardType: TextInputType.number),
            if (_type == QuestionType.short || _type == QuestionType.long)
              LabeledField(
                label: 'Grading Keywords (Optional)',
                hint: 'e.g. Force, mass, acceleration (comma separated)',
                controller: _keywordsCtrl,
              ),
            if (_type == QuestionType.mcq) ...[
              Text('OPTIONS',
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              RadioGroup<int>(
                groupValue: _correctIdx,
                onChanged: (v) => setState(() => _correctIdx = v!),
                child: Column(
                  children: _optionCtrls.asMap().entries.map((entry) {
                    final i = entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RadioListTile<int>(
                        value: i,
                        activeColor: AppColors.accent,
                        contentPadding: EdgeInsets.zero,
                        title: TextField(
                          controller: entry.value,
                          style: TextStyle(
                              color: context.appColors.textPrimary,
                              fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Option ${i + 1}',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Add Question',
              onPressed: () {
                if (_questionCtrl.text.isEmpty) return;

                final keywords = _keywordsCtrl.text
                    .split(',')
                    .map((e) => e.trim().toLowerCase())
                    .where((e) => e.isNotEmpty)
                    .toList();

                final q = QuizQuestion(
                  id: const Uuid().v4(),
                  text: _questionCtrl.text.trim(),
                  type: _type,
                  marks: double.tryParse(_marksCtrl.text) ?? 1,
                  options: _type == QuestionType.mcq
                      ? _optionCtrls.map((c) => c.text).toList()
                      : null,
                  correctIndex: _type == QuestionType.mcq ? _correctIdx : null,
                  gradingKeywords: keywords,
                );
                widget.onAdd(q);
                Navigator.pop(context);
              },
              icon: Icons.check,
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBtn(String label, QuestionType t) {
    final selected = _type == t;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _type = t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.15)
                : context.appColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? AppColors.accent : context.appColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? context.appColors.accentText
                      : context.appColors.textSecondary,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
