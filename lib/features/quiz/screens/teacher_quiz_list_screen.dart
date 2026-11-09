import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import '../../shared/documents_screen.dart';
import '../../../data/remote/file_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/quiz_model.dart';
import '../../../data/remote/pdf_generator_service.dart';
import 'create_quiz_screen.dart';
import 'mark_entry_screen.dart';
import 'ai_paper_grader_screen.dart';

class TeacherQuizListScreen extends StatefulWidget {
  final bool isAiGen;
  final String? initialClassId;
  const TeacherQuizListScreen(
      {super.key, this.isAiGen = false, this.initialClassId});

  @override
  State<TeacherQuizListScreen> createState() => _TeacherQuizListScreenState();
}

class _TeacherQuizListScreenState extends State<TeacherQuizListScreen> {
  String? _selectedClassId;
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.initialClassId;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.isAiGen ? 'AI Test Generator' : 'Grading & AI Paper Grader',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: (widget.isAiGen && _selectedClassId != null)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textOnAccent,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate AI Test'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateQuizScreen(
                    classId: _selectedClassId!,
                    isAiGen: true,
                  ),
                ),
              ),
            )
          : null,
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
      title: widget.isAiGen ? 'AI Test Generator' : 'Grading & AI Paper Grader',
      titleIcon: widget.isAiGen
          ? Icons.auto_awesome_motion_rounded
          : Icons.add_chart_rounded,
      navSections: navSections,
      activeNavId: widget.isAiGen ? 'ai_test_gen' : 'grading',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    widget.isAiGen
                        ? 'AI Test Generator'
                        : 'Grading & AI Paper Grader',
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              if (widget.isAiGen && _selectedClassId != null)
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateQuizScreen(
                        classId: _selectedClassId!,
                        isAiGen: true,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Generate AI Test'),
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
          const SizedBox(height: 16),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final classes = context
        .watch<ClassProvider>()
        .classes
        .where((c) => c.primaryTeacherId == user?.uid)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SELECT CLASS',
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.appColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedClassId,
                    hint: Text('Choose a class',
                        style:
                            TextStyle(color: context.appColors.textSecondary)),
                    dropdownColor: context.appColors.surface,
                    isExpanded: true,
                    icon: Icon(Icons.keyboard_arrow_down,
                        color: context.appColors.accentText),
                    items: classes.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Text("${c.className} (${c.section})",
                            style: TextStyle(
                                color: context.appColors.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedClassId = val),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedClassId == null
              ? _buildNoClassState()
              : _buildQuizList(_selectedClassId!),
        ),
      ],
    );
  }

  Widget _buildNoClassState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.class_outlined,
              size: 64,
              color: context.appColors.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Select a class to view tests',
              style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildQuizList(String classId) {
    final user = context.read<AuthProvider>().currentUser;
    return StreamBuilder<List<QuizModel>>(
      stream: context
          .read<QuizProvider>()
          .watchTeacherQuizzes(classId, user?.academyId ?? ''),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading tests: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          );
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
              child: Text('No tests created yet',
                  style: TextStyle(color: context.appColors.textSecondary)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _quizTile(list[i]),
        );
      },
    );
  }

  /// PDF banane ka kaam try-catch mein — error aaye toh SnackBar dikhega
  Future<void> _runPdfAction(
      Future<void> Function() action, String failMsg) async {
    if (_pdfBusy) return; // double-tap se bachao
    setState(() => _pdfBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('$failMsg: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Widget _quizTile(QuizModel quiz) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.description_rounded,
                    color: context.appColors.accentText),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quiz.title,
                        style: TextStyle(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16)),
                    Text(
                        "${quiz.subject} • ${quiz.month} • ${quiz.totalMarks} Marks",
                        style: TextStyle(
                            color: context.appColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Exam documents',
                icon: Icon(Icons.folder_rounded,
                    color: context.appColors.accentText, size: 20),
                // Question papers, answer keys, result sheets for this test.
                // Visible to the class teacher and admins only.
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DocumentsScreen(
                      title: '${quiz.title} · Documents',
                      subtitle: 'Exam paper, answer key and result sheets. '
                          'Only the class teacher and academy admins can see these.',
                      category: FileCategory.examDocument,
                      ownerId: quiz.id,
                      canEdit: true,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Delete test',
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 20),
                onPressed: () => _confirmDelete(quiz),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.isAiGen)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pdfBusy
                        ? null
                        : () => _runPdfAction(
                              () => PdfGeneratorService.printTestPaper(quiz),
                              'Could not open print preview',
                            ),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text("PRINT"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pdfBusy
                        ? null
                        : () => _runPdfAction(
                              () => PdfGeneratorService.shareTestPaper(quiz),
                              'Could not share PDF',
                            ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text("SHARE PDF"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textOnAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AiPaperGraderScreen(quiz: quiz)),
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text("AI SMART GRADER"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      foregroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      side: const BorderSide(color: AppColors.accent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MarkEntryScreen(quiz: quiz)),
                    ),
                    icon: const Icon(Icons.add_chart_rounded, size: 18),
                    label: const Text("ENTER MARKS"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textOnAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(QuizModel quiz) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: Text('Delete Test?',
            style: TextStyle(color: context.appColors.textPrimary)),
        content: Text(
            'This will remove the test and all student marks permanently.',
            style: TextStyle(color: context.appColors.textSecondary)),
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
    if (ok == true && mounted) {
      try {
        await context.read<QuizProvider>().deleteQuiz(quiz.id, quiz.academyId);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Test deleted.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to delete test: $e'),
              backgroundColor: AppColors.danger));
        }
      }
    }
  }
}
