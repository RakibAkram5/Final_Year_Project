import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/quiz_model.dart';
import '../../../data/models/quiz_submission_model.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

/// One submitted attempt, question by question.
///
/// * Students and parents see it read-only after submission: their answer,
///   whether each MCQ was right, the auto score and (once graded) the final
///   score and teacher note.
/// * Teachers/admins ([canGrade]) additionally enter marks for short/long
///   answers and a note; saving publishes the result as a TestMark once every
///   question has a score.
class SubmissionReviewScreen extends StatefulWidget {
  final QuizModel quiz;
  final QuizSubmission submission;
  final bool canGrade;

  const SubmissionReviewScreen({
    super.key,
    required this.quiz,
    required this.submission,
    required this.canGrade,
  });

  @override
  State<SubmissionReviewScreen> createState() => _SubmissionReviewScreenState();
}

class _SubmissionReviewScreenState extends State<SubmissionReviewScreen> {
  late QuizSubmission _sub = widget.submission;
  final Map<String, TextEditingController> _marks = {};
  late final TextEditingController _note =
      TextEditingController(text: widget.submission.teacherNote);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final q in widget.quiz.questions) {
      if (q.type != QuestionType.mcq) {
        final awarded = _sub.answerFor(q.id)?.marksAwarded;
        _marks[q.id] =
            TextEditingController(text: awarded == null ? '' : _fmt(awarded));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _marks.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Future<void> _saveGrades() async {
    final byQuestion = <String, double>{};
    for (final q in widget.quiz.questions) {
      final ctrl = _marks[q.id];
      if (ctrl == null) continue;
      final text = ctrl.text.trim();
      if (text.isEmpty) continue;
      final v = double.tryParse(text);
      if (v == null || v < 0 || v > q.marks) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(
                'Marks for "${q.text.length > 40 ? '${q.text.substring(0, 40)}…' : q.text}" must be between 0 and ${_fmt(q.marks)}.')));
        return;
      }
      byQuestion[q.id] = v;
    }
    setState(() => _saving = true);
    try {
      final updated = await context.read<QuizProvider>().gradeSubmission(
            widget.quiz.id,
            _sub.id,
            marksByQuestion: byQuestion,
            teacherNote: _note.text.trim(),
          );
      if (!mounted) return;
      setState(() => _sub = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.success,
          content: Text(updated.needsReview
              ? 'Marks saved. Some questions are still ungraded.'
              : 'Graded. The result is now visible to the student and parents.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Could not save marks: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final title =
        widget.canGrade ? (_sub.studentName ?? 'Submission') : 'Your result';
    final body = Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _body(context)),
    );
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      void onDashboard() => Navigator.of(context).popUntil((r) => r.isFirst);
      final nav = switch (user?.role) {
        UserRole.student =>
          buildStudentNavSections(context, onDashboard: onDashboard),
        UserRole.parent =>
          buildParentNavSections(context, onDashboard: onDashboard),
        UserRole.admin =>
          buildAdminNavSections(context, onDashboard: onDashboard),
        UserRole.teacher =>
          buildTeacherNavSections(context, onDashboard: onDashboard),
        null => const <WebNavSection>[],
      };
      return WebAppShell(
        title: title,
        titleIcon: Icons.fact_check_rounded,
        navSections: nav,
        activeNavId: widget.canGrade ? 'grading' : 'online_tests',
        user: user,
        onLogout: () => performWebLogout(context),
        body: body,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(child: SafeArea(child: body)),
    );
  }

  Widget _body(BuildContext context) {
    final quiz = widget.quiz;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(context),
        const SizedBox(height: 14),
        ...List.generate(
            quiz.questions.length, (i) => _questionTile(context, i)),
        if (widget.canGrade) ...[
          const SizedBox(height: 8),
          Text('TEACHER NOTE',
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 3,
            style: TextStyle(color: context.appColors.textPrimary),
            decoration: const InputDecoration(
                hintText: 'Optional feedback shown to the student and parents'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving || _sub.isInProgress ? null : _saveGrades,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_sub.isInProgress
                ? 'Student has not submitted yet'
                : (_saving ? 'Saving…' : 'Save marks & publish result')),
          ),
        ] else if (_sub.teacherNote.isNotEmpty) ...[
          const SizedBox(height: 8),
          _noteCard(context),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _summaryCard(BuildContext context) {
    final quiz = widget.quiz;
    final df = DateFormat('d MMM yyyy, h:mm a');
    final status = switch (_sub.status) {
      SubmissionStatus.graded => ('Graded', AppColors.success),
      SubmissionStatus.submitted => (
          'Awaiting teacher review',
          AppColors.warning
        ),
      SubmissionStatus.inProgress => (
          'In progress',
          context.appColors.textMuted
        ),
    };
    final score = _sub.finalScore ?? _sub.autoScore;
    final outOf = _sub.finalScore != null
        ? quiz.totalMarks
        : (_sub.autoMaxScore ?? quiz.totalMarks);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quiz.title,
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${quiz.subject} • ${quiz.classLabel}',
              style: TextStyle(
                  color: context.appColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _pill(context, status.$1, status.$2),
              if (score != null)
                _pill(
                    context,
                    _sub.finalScore != null
                        ? 'Score ${_fmt(score)} / ${_fmt(outOf)}'
                        : 'Objective score ${_fmt(score)} / ${_fmt(outOf)}',
                    AppColors.accent),
              if (_sub.finalScore != null && quiz.totalMarks > 0)
                _pill(
                    context,
                    '${(_sub.finalScore! / quiz.totalMarks * 100).toStringAsFixed(0)}%',
                    AppColors.accent),
            ],
          ),
          if (_sub.needsReview && !widget.canGrade) ...[
            const SizedBox(height: 10),
            Text(
                'Multiple-choice questions were marked automatically. Written answers are waiting for your teacher; the final score will appear here once graded.',
                style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4)),
          ],
          const SizedBox(height: 10),
          Text(
              [
                if (_sub.submittedAt != null)
                  'Submitted ${df.format(_sub.submittedAt!)}',
                if (_sub.gradedAt != null)
                  'Graded ${df.format(_sub.gradedAt!)}',
              ].join(' • '),
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color == AppColors.accent
                  ? context.appColors.accentText
                  : color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _noteCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.rate_review_rounded,
              size: 18, color: context.appColors.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Teacher feedback',
                    style: TextStyle(
                        color: context.appColors.accentText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(_sub.teacherNote,
                    style: TextStyle(color: context.appColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionTile(BuildContext context, int i) {
    final q = widget.quiz.questions[i];
    final a = _sub.answerFor(q.id);
    final isMcq = q.type == QuestionType.mcq;
    final correctIndex = _sub.correctIndexes[q.id];
    final awarded = a?.marksAwarded;
    Color edge = context.appColors.border.withValues(alpha: 0.6);
    if (isMcq && a?.isCorrect != null) {
      edge = a!.isCorrect! ? AppColors.success : AppColors.danger;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Q${i + 1}. ${q.text}',
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),
              ),
              const SizedBox(width: 10),
              Text(
                  awarded != null
                      ? '${_fmt(awarded)} / ${_fmt(q.marks)}'
                      : '— / ${_fmt(q.marks)}',
                  style: TextStyle(
                      color: awarded == null
                          ? context.appColors.textMuted
                          : (awarded >= q.marks
                              ? AppColors.success
                              : (awarded == 0
                                  ? AppColors.danger
                                  : AppColors.warning)),
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          if (isMcq && (q.options?.isNotEmpty ?? false))
            ...List.generate(q.options!.length, (oi) {
              final chosen = a?.selectedIndex == oi;
              final isKey = correctIndex == oi;
              Color? c;
              if (isKey) c = AppColors.success;
              if (chosen && !isKey && correctIndex != null) {
                c = AppColors.danger;
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                        chosen
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 18,
                        color: c ?? context.appColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '${String.fromCharCode(65 + oi)}. ${q.options![oi]}',
                          style: TextStyle(
                              color: c ?? context.appColors.textSecondary,
                              fontWeight:
                                  chosen || isKey ? FontWeight.w700 : null)),
                    ),
                    if (isKey)
                      const Icon(Icons.check_rounded,
                          size: 16, color: AppColors.success),
                  ],
                ),
              );
            })
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                  (a?.answerText.trim().isNotEmpty ?? false)
                      ? a!.answerText
                      : 'No answer written.',
                  style: TextStyle(
                      color: (a?.answerText.trim().isNotEmpty ?? false)
                          ? context.appColors.textPrimary
                          : context.appColors.textMuted,
                      fontStyle: (a?.answerText.trim().isNotEmpty ?? false)
                          ? null
                          : FontStyle.italic)),
            ),
            if (widget.canGrade) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _marks[q.id],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: context.appColors.textPrimary),
                      decoration: InputDecoration(
                          labelText: 'Marks', hintText: '0–${_fmt(q.marks)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (q.answerText != null && q.answerText!.trim().isNotEmpty)
                    Expanded(
                      child: Text('Model answer: ${q.answerText}',
                          style: TextStyle(
                              color: context.appColors.textMuted,
                              fontSize: 12.5)),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
