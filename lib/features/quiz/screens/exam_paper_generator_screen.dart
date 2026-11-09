import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../logic/session_provider.dart';
import '../../../logic/exam_paper_generator.dart';
import '../../../data/exam/curriculum_bank.dart';
import '../../../data/models/quiz_model.dart';
import '../../../data/remote/pdf_generator_service.dart';
import '../../../data/remote/quiz_service.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

/// Professional Pakistani examination-paper generator.
///
/// Teachers configure the paper (subject, chapters, exam type, section counts,
/// marks, attempt-any rules, difficulty, language), generate it from the
/// vetted curriculum bank and/or scanned source material, then preview, print,
/// download the student paper and a separate teacher answer key, or save the
/// paper to examination history.
class ExamPaperGeneratorScreen extends StatefulWidget {
  final String classId;
  const ExamPaperGeneratorScreen({super.key, required this.classId});

  @override
  State<ExamPaperGeneratorScreen> createState() =>
      _ExamPaperGeneratorScreenState();
}

class _ExamPaperGeneratorScreenState extends State<ExamPaperGeneratorScreen> {
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController(text: 'Computer Science');
  final _timeCtrl = TextEditingController(text: '2 hours');
  final _chaptersCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();

  final _mcqCountCtrl = TextEditingController(text: '10');
  final _marksPerMcqCtrl = TextEditingController(text: '1');
  final _shortGroupsCtrl = TextEditingController(text: '2');
  final _partsPerGroupCtrl = TextEditingController(text: '6');
  final _attemptPerGroupCtrl = TextEditingController(text: '4');
  final _marksPerShortCtrl = TextEditingController(text: '2');
  final _longCountCtrl = TextEditingController(text: '3');
  final _longAttemptCtrl = TextEditingController(text: '2');
  final _marksPerLongCtrl = TextEditingController(text: '8');

  String _examType = 'Monthly Test';
  String _difficulty = 'Medium';
  String _language = 'en';

  final _generator = ExamPaperGenerator();
  final _quizService = QuizService();
  GenerationResult? _result;
  bool _generating = false;
  bool _saving = false;
  bool _ocrBusy = false;
  bool _useAi = false;

  static const _examTypes = [
    'Monthly Test',
    'Weekly Test',
    'Midterm',
    'Final Term',
    'Practice Test',
  ];

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _subjectCtrl,
      _timeCtrl,
      _chaptersCtrl,
      _sourceCtrl,
      _targetCtrl,
      _mcqCountCtrl,
      _marksPerMcqCtrl,
      _shortGroupsCtrl,
      _partsPerGroupCtrl,
      _attemptPerGroupCtrl,
      _marksPerShortCtrl,
      _longCountCtrl,
      _longAttemptCtrl,
      _marksPerLongCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;
  double _double(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim()) ?? fallback;

  List<String> get _chapters => _chaptersCtrl.text
      .split(RegExp(r'[,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  ExamConfig _buildConfig(String classLabel) {
    final groups = <ShortGroupConfig>[];
    final groupCount = _int(_shortGroupsCtrl, 0).clamp(0, 6);
    for (var i = 0; i < groupCount; i++) {
      groups.add(ShortGroupConfig(
        partsCount: _int(_partsPerGroupCtrl, 6).clamp(1, 20),
        attemptCount: _int(_attemptPerGroupCtrl, 4).clamp(1, 20),
        marksPerPart: _double(_marksPerShortCtrl, 2),
      ));
    }
    return ExamConfig(
      title: _titleCtrl.text.trim(),
      subject: _subjectCtrl.text.trim(),
      classLabel: classLabel,
      examType: _examType,
      timeAllowed: _timeCtrl.text.trim(),
      difficulty: _difficulty,
      language: _language,
      chapters: _chapters,
      mcqCount: _int(_mcqCountCtrl, 10).clamp(0, 60),
      marksPerMcq: _double(_marksPerMcqCtrl, 1),
      shortGroups: groups,
      longCount: _int(_longCountCtrl, 3).clamp(0, 20),
      longAttempt: _int(_longAttemptCtrl, 2).clamp(0, 20),
      marksPerLong: _double(_marksPerLongCtrl, 8),
      sourceText: _sourceCtrl.text.trim().isEmpty ? null : _sourceCtrl.text,
    );
  }

  MarksBreakdown _liveMarks() {
    final target = double.tryParse(_targetCtrl.text.trim());
    return _generator.validateMarks(_buildConfig(''), target: target);
  }

  Future<void> _generate() async {
    final auth = context.read<AuthProvider>();
    final cp = context.read<ClassProvider>();
    final user = auth.currentUser;
    if (user == null) {
      _snack('Session expired. Please log in again.', error: true);
      return;
    }
    final matches = cp.classes.where((c) => c.id == widget.classId).toList();
    if (matches.isEmpty) {
      _snack('This class no longer exists.', error: true);
      return;
    }
    final cls = matches.first;
    final classLabel = '${cls.className} (${cls.section})';

    if (_subjectCtrl.text.trim().isEmpty) {
      _snack('Please enter a subject.', error: true);
      return;
    }

    setState(() => _generating = true);
    try {
      final config = _buildConfig(classLabel);

      // Optional AI path: try the server LLM first (if the teacher opted in
      // and the server has a key); on any failure fall back to offline.
      var remoteItems = const <BankItem>[];
      if (_useAi) {
        final shortCount =
            config.shortGroups.fold<int>(0, (s, g) => s + g.partsCount);
        final items = await _quizService.aiGenerateItems(
          subject: config.subject,
          classLabel: classLabel,
          chapters: config.chapters,
          difficulty: config.difficulty,
          mcqCount: config.mcqCount,
          shortCount: shortCount,
          longCount: config.longCount,
        );
        if (items == null) {
          _snack('AI generation is not available — using offline generator.');
        } else if (items.isEmpty) {
          _snack('AI returned no usable questions — using offline generator.');
        } else {
          remoteItems = items;
        }
      }

      final result = _generator.generate(
        config,
        academyId: user.academyId ?? '',
        classId: widget.classId,
        createdByUid: user.uid,
        createdByName: user.fullName,
        remoteItems: remoteItems,
      );
      setState(() => _result = result);
      if (!result.ok) {
        _snack(result.error ?? 'Generation failed.', error: true);
      } else {
        final warn = result.warnings.isEmpty
            ? ''
            : ' (${result.warnings.length} note(s) — see below)';
        _snack('Paper generated: ${result.quiz!.questions.length} questions, '
            '${_fmt(result.quiz!.computedTotalMarks)} marks$warn.');
      }
    } catch (e) {
      _snack('Generation error: $e', error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _scanSource() async {
    if (kIsWeb) {
      _snack('Scanning is available on the mobile app. Paste notes instead.',
          error: true);
      return;
    }
    final picker = ImagePicker();
    final session = context.read<SessionProvider>();
    session.suppressBackgroundLogout();
    XFile? file;
    try {
      file = await picker.pickImage(source: ImageSource.camera);
    } catch (_) {
      try {
        file = await picker.pickImage(source: ImageSource.gallery);
      } catch (_) {}
    } finally {
      session.resumeBackgroundLogoutTracking();
    }
    if (file == null) return;
    setState(() => _ocrBusy = true);
    try {
      final recognizer = TextRecognizer();
      final text =
          await recognizer.processImage(InputImage.fromFile(File(file.path)));
      await recognizer.close();
      if (text.text.trim().isEmpty) {
        _snack('No text detected in the image.', error: true);
      } else {
        setState(() {
          _sourceCtrl.text = (_sourceCtrl.text.trim().isEmpty
              ? text.text
              : '${_sourceCtrl.text}\n${text.text}');
        });
        _snack('Scanned ${text.text.length} characters into source material.');
      }
    } catch (e) {
      _snack('Scan failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<void> _runPdf(Future<void> Function() action, String busyLabel) async {
    try {
      await action();
    } catch (e) {
      _snack('$busyLabel failed: $e', error: true);
    }
  }

  Future<void> _preview(bool answerKey) async {
    final quiz = _result?.quiz;
    if (quiz == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
            title: Text(answerKey ? 'Answer Key Preview' : 'Paper Preview')),
        body: PdfPreview(
          build: (format) => answerKey
              ? PdfGeneratorService.answerKeyBytes(quiz)
              : PdfGeneratorService.studentPaperBytes(quiz),
          canChangePageFormat: false,
          canChangeOrientation: false,
          pdfFileName:
              '${quiz.title}${answerKey ? '_Answer_Key' : '_Paper'}.pdf',
        ),
      ),
    ));
  }

  Future<void> _save() async {
    final quiz = _result?.quiz;
    if (quiz == null) return;
    setState(() => _saving = true);
    try {
      await context.read<QuizProvider>().createQuiz(quiz);
      if (mounted) {
        _snack('Paper saved to examination history.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      _snack('Save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.success,
    ));
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      final navSections = buildTeacherNavSections(context,
          onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
      return WebAppShell(
        title: 'AI Exam Paper Generator',
        titleIcon: Icons.auto_awesome_motion_rounded,
        navSections: navSections,
        activeNavId: 'ai_test_gen',
        user: context.watch<AuthProvider>().currentUser,
        onLogout: () => performWebLogout(context),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: _body(),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Exam Paper Generator',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(child: SafeArea(child: _body())),
    );
  }

  Widget _body() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _section('PAPER DETAILS', [
          LabeledField(
              label: 'Paper Title (optional)',
              hint: 'e.g. First Monthly Test',
              controller: _titleCtrl),
          LabeledField(
              label: 'Subject',
              hint: 'e.g. Computer Science',
              controller: _subjectCtrl),
          _subjectChips(),
          Row(children: [
            Expanded(
                child: _dropdown('Exam Type', _examType, _examTypes,
                    (v) => setState(() => _examType = v!))),
            const SizedBox(width: 12),
            Expanded(
                child: LabeledField(
                    label: 'Time Allowed',
                    hint: 'e.g. 2 hours',
                    controller: _timeCtrl)),
          ]),
          LabeledField(
              label: 'Chapters (comma separated, optional)',
              hint: 'e.g. Data and Number Systems, Computer Architecture',
              controller: _chaptersCtrl),
          _chapterChips(),
          Row(children: [
            Expanded(
                child: _dropdown(
                    'Difficulty',
                    _difficulty,
                    const ['Easy', 'Medium', 'Hard', 'Mixed'],
                    (v) => setState(() => _difficulty = v!))),
            const SizedBox(width: 12),
            Expanded(
                child: _dropdown('Language', _language, const ['en', 'ur'],
                    (v) => setState(() => _language = v!),
                    labels: const {'en': 'English', 'ur': 'Urdu'})),
          ]),
          if (_language == 'ur')
            _note('Urdu is selected. Urdu text you add will generate, but the '
                'bundled fonts render Latin script; Urdu glyphs need the Urdu '
                'font pack (coming soon) to display correctly in the PDF.'),
        ]),
        _section('SECTION A — MCQs', [
          Row(children: [
            Expanded(child: _numField('Number of MCQs', _mcqCountCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _numField('Marks each', _marksPerMcqCtrl)),
          ]),
        ]),
        _section('SHORT QUESTIONS', [
          Row(children: [
            Expanded(child: _numField('Groups', _shortGroupsCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _numField('Parts / group', _partsPerGroupCtrl)),
          ]),
          Row(children: [
            Expanded(child: _numField('Attempt any', _attemptPerGroupCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _numField('Marks / part', _marksPerShortCtrl)),
          ]),
        ]),
        _section('PART II — LONG QUESTIONS', [
          Row(children: [
            Expanded(child: _numField('Printed', _longCountCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _numField('Attempt any', _longAttemptCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _numField('Marks each', _marksPerLongCtrl)),
          ]),
        ]),
        _section('SOURCE MATERIAL (OPTIONAL)', [
          _note('Paste or scan textbook/notes to generate questions from your '
              'own material. Left empty, the paper is built from the vetted '
              'curriculum bank for the subject.'),
          const SizedBox(height: 8),
          TextField(
            controller: _sourceCtrl,
            maxLines: 5,
            minLines: 3,
            decoration: InputDecoration(
              hintText: 'Paste source text here (optional)...',
              filled: true,
              fillColor: context.appColors.inputFill,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _ocrBusy ? null : _scanSource,
            icon: _ocrBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner_outlined),
            label: Text(_ocrBusy ? 'Scanning...' : 'Scan page (mobile)'),
          ),
        ]),
        const SizedBox(height: 8),
        _marksSummary(),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _useAi,
          activeThumbColor: AppColors.accent,
          onChanged: (v) => setState(() => _useAi = v),
          title: Text('Use AI generation (if enabled on server)',
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          subtitle: Text(
              'Falls back to the offline curriculum generator automatically '
              'when no AI key is configured.',
              style: TextStyle(
                  color: context.appColors.textMuted, fontSize: 11.5)),
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'Generate Professional Paper',
          icon: Icons.auto_awesome,
          loading: _generating,
          onPressed: _generating ? null : _generate,
        ),
        const SizedBox(height: 20),
        if (_result != null && _result!.ok) _resultPanel(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _marksSummary() {
    final m = _liveMarks();
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
              Text(value,
                  style: TextStyle(
                      color: bold
                          ? context.appColors.accentText
                          : context.appColors.textPrimary,
                      fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MARKS SUMMARY',
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          row('Section A (MCQs)', _fmt(m.mcqMarks)),
          row('Short questions', _fmt(m.shortMarks)),
          row('Part II (long)', _fmt(m.longMarks)),
          const Divider(),
          row('Computed total', _fmt(m.total), bold: true),
          const SizedBox(height: 8),
          LabeledField(
            label: 'Expected total (optional — to cross-check)',
            hint: 'e.g. 50',
            controller: _targetCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          if (m.mismatch)
            _note(
                '⚠ The expected total (${_fmt(m.configuredTarget!)}) does not '
                'match the computed total (${_fmt(m.total)}). The paper always '
                'prints the computed total so the marks are never wrong.',
                warn: true),
        ],
      ),
    );
  }

  Widget _resultPanel() {
    final result = _result!;
    final quiz = result.quiz!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Generated — ${quiz.questions.length} questions · '
                '${_fmt(quiz.computedTotalMarks)} marks · engine: '
                '${result.engine}',
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.warnings.map((w) => _note(w, warn: true)),
          ],
          const SizedBox(height: 12),
          _previewList(quiz),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _action('Preview Paper', Icons.visibility_outlined,
                  () => _preview(false)),
              _action(
                  'Print Paper',
                  Icons.print_outlined,
                  () => _runPdf(
                      () => PdfGeneratorService.printTestPaper(quiz), 'Print')),
              _action(
                  'Download Paper',
                  Icons.download_outlined,
                  () => _runPdf(() => PdfGeneratorService.shareTestPaper(quiz),
                      'Download')),
              _action(
                  'Answer Key (PDF)',
                  Icons.vpn_key_outlined,
                  () => _runPdf(() => PdfGeneratorService.shareAnswerKey(quiz),
                      'Answer key'),
                  highlight: true),
              _action('Preview Key', Icons.visibility_outlined,
                  () => _preview(true)),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Save to Examination History',
            icon: Icons.save_outlined,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _previewList(QuizModel quiz) {
    final widgets = <Widget>[];
    var block = 1;
    for (final s in quiz.sections) {
      final qs = s.questionIds
          .map(quiz.questionById)
          .whereType<QuizQuestion>()
          .toList();
      final label = switch (s.kind) {
        SectionKind.mcq => 'Section A — MCQs (${qs.length})',
        SectionKind.short =>
          '$block. Short — attempt any ${s.attemptCount} of ${qs.length}',
        SectionKind.long =>
          'Part II — Long (attempt any ${s.attemptCount} of ${qs.length})',
      };
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(label,
            style: TextStyle(
                color: context.appColors.accentText,
                fontWeight: FontWeight.w800,
                fontSize: 12)),
      ));
      for (var i = 0; i < qs.length; i++) {
        final q = qs[i];
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Text(
            '${i + 1}. ${q.text}',
            style: TextStyle(
                color: context.appColors.textSecondary, fontSize: 12.5),
          ),
        ));
      }
      block++;
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _action(String label, IconData icon, VoidCallback onTap,
      {bool highlight = false}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            highlight ? AppColors.accent : context.appColors.textPrimary,
        side: BorderSide(
            color: highlight ? AppColors.accent : context.appColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _subjectChips() {
    const subjects = ['Computer Science', 'Mathematics', 'English'];
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(
        spacing: 8,
        children: subjects
            .map((s) => ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: () => setState(() {
                    _subjectCtrl.text = s;
                    _chaptersCtrl.clear();
                  }),
                ))
            .toList(),
      ),
    );
  }

  Widget _chapterChips() {
    final chapters = CurriculumBank.chaptersFor(_subjectCtrl.text);
    if (chapters.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: chapters.map((c) {
          final selected =
              _chapters.map((e) => e.toLowerCase()).contains(c.toLowerCase());
          return FilterChip(
            label: Text(c, style: const TextStyle(fontSize: 11)),
            selected: selected,
            onSelected: (v) {
              final current = _chapters;
              if (v) {
                current.add(c);
              } else {
                current.removeWhere((e) => e.toLowerCase() == c.toLowerCase());
              }
              setState(() => _chaptersCtrl.text = current.join(', '));
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctrl) {
    return LabeledField(
      label: label,
      hint: '0',
      controller: ctrl,
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title,
            style: TextStyle(
                color: context.appColors.accentText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _dropdown(String label, String value, List<String> items,
      ValueChanged<String?> onChanged,
      {Map<String, String>? labels}) {
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
              isExpanded: true,
              dropdownColor: context.appColors.surface,
              items: items
                  .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(labels?[m] ?? m,
                          style:
                              TextStyle(color: context.appColors.textPrimary))))
                  .toList(),
              onChanged: onChanged,
              icon: Icon(Icons.keyboard_arrow_down,
                  color: context.appColors.accentText),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _note(String text, {bool warn = false}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (warn ? AppColors.warning : AppColors.accent)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
              height: 1.4)),
    );
  }
}
