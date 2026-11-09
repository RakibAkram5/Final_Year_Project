import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/quiz_model.dart';
import '../quiz/screens/quiz_results_screen.dart';

class AdminQuizListScreen extends StatefulWidget {
  const AdminQuizListScreen({super.key});

  @override
  State<AdminQuizListScreen> createState() => _AdminQuizListScreenState();
}

class _AdminQuizListScreenState extends State<AdminQuizListScreen> {
  String? _selectedClassId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final academyId =
          Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
              '';
      context.read<ClassProvider>().listenAll(academyId);
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
    final classes = context.watch<ClassProvider>().classes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Reports & Grading',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FILTER BY CLASS',
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
                          hint: Text('All Classes',
                              style: TextStyle(
                                  color: context.appColors.textSecondary)),
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
                          onChanged: (val) =>
                              setState(() => _selectedClassId = val),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _selectedClassId == null
                    ? _buildAllQuizzes()
                    : _buildQuizList(_selectedClassId!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final classes = context.watch<ClassProvider>().classes;
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));

    return WebAppShell(
      title: 'Test Reports & Grading',
      titleIcon: Icons.analytics_rounded,
      navSections: navSections,
      activeNavId: 'quiz_reports',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Test Reports & Grading',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: context.appColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Pick a class to review its test results.',
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 20),
          SizedBox(
            width: 340,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: context.appColors.inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.appColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedClassId,
                  hint: Text('All Classes',
                      style: TextStyle(color: context.appColors.textSecondary)),
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down,
                      color: context.appColors.accentText),
                  items: classes.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Text("${c.className} (${c.section})",
                          style:
                              TextStyle(color: context.appColors.textPrimary)),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedClassId = val),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _selectedClassId == null
                ? _buildAllQuizzes()
                : _buildQuizList(_selectedClassId!),
          ),
        ],
      ),
    );
  }

  Widget _buildAllQuizzes() {
    return Center(
      child: Text('Select a class to view test reports',
          style: TextStyle(color: context.appColors.textSecondary)),
    );
  }

  Widget _buildQuizList(String classId) {
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
            '';
    return StreamBuilder<List<QuizModel>>(
      stream:
          context.read<QuizProvider>().watchTeacherQuizzes(classId, academyId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snap.hasError) {
          return Center(
              child: Text('Error loading tests: ${snap.error}',
                  style: const TextStyle(color: AppColors.danger)));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
              child: Text('No tests found for this class',
                  style: TextStyle(color: context.appColors.textSecondary)));
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _quizTile(list[i]),
        );
      },
    );
  }

  Widget _quizTile(QuizModel quiz) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QuizResultsScreen(quiz: quiz)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.appColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.appColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.analytics_rounded,
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
                    Text("${quiz.subject} • ${quiz.totalMarks} Marks",
                        style: TextStyle(
                            color: context.appColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.appColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
