import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/quiz_model.dart';
import '../../../data/models/test_mark_model.dart';
import 'quiz_submissions_screen.dart';

class QuizResultsScreen extends StatelessWidget {
  final QuizModel quiz;
  const QuizResultsScreen({super.key, required this.quiz});

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
        title: const Text('Test Results',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(context),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Test Results',
      titleIcon: Icons.analytics_rounded,
      navSections: navSections,
      activeNavId: 'quiz_reports',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Test Results',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _quizHeader(context),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text('STUDENT RECORDS',
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
        Expanded(
          child: StreamBuilder<List<TestMarkModel>>(
            stream: context
                .read<QuizProvider>()
                .watchQuizResults(quiz.id, quiz.academyId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent));
              }
              if (snap.hasError) {
                return Center(
                    child: Text('Error loading marks: ${snap.error}',
                        style: const TextStyle(color: AppColors.danger)));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return Center(
                    child: Text('No marks uploaded yet',
                        style:
                            TextStyle(color: context.appColors.textSecondary)));
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _markTile(context, list[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _quizHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quiz.title,
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text("${quiz.subject} • Total Marks: ${quiz.totalMarks}",
              style: TextStyle(
                  color: context.appColors.textPrimary, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 14, color: context.appColors.textMuted),
              const SizedBox(width: 6),
              Text("Date: ${DateFormat('MMM d, yyyy').format(quiz.testDate)}",
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 12)),
            ],
          ),
          if (quiz.isOnline) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => QuizSubmissionsScreen(quiz: quiz)),
              ),
              icon: const Icon(Icons.fact_check_rounded, size: 18),
              label: const Text('Online submissions & grading'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _markTile(BuildContext context, TestMarkModel mark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _editMark(context, mark),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.appColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.appColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mark.studentName,
                        style: TextStyle(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text("Grade: ${mark.gradeLetter}",
                        style: TextStyle(
                            color: _getGradeColor(mark.gradeLetter),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${mark.marksObtained} / ${mark.totalMarks}",
                      style: TextStyle(
                          color: context.appColors.accentText,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text("${mark.percentage.toStringAsFixed(1)}%",
                      style: TextStyle(
                          color: context.appColors.textMuted, fontSize: 11)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 20),
                tooltip: 'Delete mark',
                onPressed: () => _deleteMark(context, mark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editMark(BuildContext context, TestMarkModel mark) async {
    final ctrl =
        TextEditingController(text: mark.marksObtained.toStringAsFixed(1));

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: Text("Edit ${mark.studentName}'s Marks",
            style: TextStyle(color: context.appColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: 'Out of ${mark.totalMarks}'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.trim());
              if (val == null || val < 0 || val > mark.totalMarks) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content:
                        Text('Enter a value between 0 and ${mark.totalMarks}'),
                    backgroundColor: AppColors.danger));
                return;
              }
              Navigator.pop(ctx, val);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;

    final percentage =
        mark.totalMarks == 0 ? 0.0 : (result / mark.totalMarks) * 100;
    final updated = TestMarkModel(
      id: mark.id,
      academyId: mark.academyId,
      quizId: mark.quizId,
      studentId: mark.studentId,
      studentName: mark.studentName,
      classId: mark.classId,
      subject: mark.subject,
      month: mark.month,
      marksObtained: result,
      totalMarks: mark.totalMarks,
      percentage: percentage,
      gradeLetter: TestMarkModel.calculateGrade(percentage),
      teacherFeedback: mark.teacherFeedback,
      updatedAt: DateTime.now(),
    );

    try {
      await context.read<QuizProvider>().uploadBulkMarks([updated]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to update mark: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Future<void> _deleteMark(BuildContext context, TestMarkModel mark) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: Text('Delete this mark?',
            style: TextStyle(color: context.appColors.textPrimary)),
        content: Text("Remove ${mark.studentName}'s mark for this test?",
            style: TextStyle(color: context.appColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('DELETE',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await context.read<QuizProvider>().deleteMark(mark.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to delete mark: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Color _getGradeColor(String grade) {
    if (grade.startsWith('A')) return AppColors.success;
    if (grade == 'B' || grade == 'C') return AppColors.warning;
    return AppColors.danger;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: Text('Delete Records?',
            style: TextStyle(color: context.appColors.textPrimary)),
        content: Text(
            'This will remove the test and all associated marks permanently.',
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
    if (ok == true) {
      if (!context.mounted) return;
      try {
        await context.read<QuizProvider>().deleteQuiz(quiz.id, quiz.academyId);
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to delete test: $e'),
              backgroundColor: AppColors.danger));
        }
      }
    }
  }
}
