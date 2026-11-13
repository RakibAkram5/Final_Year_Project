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
import '../../../logic/class_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import 'submission_review_screen.dart';

/// Teacher/admin view of every student's attempt at an ONLINE quiz, with
/// who has not started, who is awaiting review and who is graded.
class QuizSubmissionsScreen extends StatelessWidget {
  final QuizModel quiz;
  const QuizSubmissionsScreen({super.key, required this.quiz});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final body = Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _body(context)));
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      void onDashboard() => Navigator.of(context).popUntil((r) => r.isFirst);
      return WebAppShell(
        title: '${quiz.title} · Submissions',
        titleIcon: Icons.fact_check_rounded,
        navSections: user?.role == UserRole.admin
            ? buildAdminNavSections(context, onDashboard: onDashboard)
            : buildTeacherNavSections(context, onDashboard: onDashboard),
        activeNavId: user?.role == UserRole.admin ? 'quiz_reports' : 'grading',
        user: user,
        onLogout: () => performWebLogout(context),
        body: body,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submissions',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(child: SafeArea(child: body)),
    );
  }

  Widget _body(BuildContext context) {
    final cls = context
        .watch<ClassProvider>()
        .classes
        .where((c) => c.id == quiz.classId)
        .toList();
    final roster = cls.isEmpty ? <String, String>{} : cls.first.studentNames;
    return StreamBuilder<List<QuizSubmission>>(
      stream: context.read<QuizProvider>().watchSubmissions(quiz.id),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load submissions: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger))));
        }
        final subs = snap.data;
        if (subs == null) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        final byStudent = {for (final s in subs) s.studentId: s};
        final notStarted = roster.keys
            .where((id) => !byStudent.containsKey(id))
            .toList()
          ..sort((a, b) => (roster[a] ?? '').compareTo(roster[b] ?? ''));
        final review =
            subs.where((s) => s.status == SubmissionStatus.submitted).toList();
        final graded =
            subs.where((s) => s.status == SubmissionStatus.graded).toList();
        final inProgress =
            subs.where((s) => s.status == SubmissionStatus.inProgress).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _summary(context, review.length, graded.length, inProgress.length,
                notStarted.length),
            if (review.isNotEmpty) ...[
              _label(context, 'AWAITING YOUR REVIEW'),
              ...review.map((s) => _tile(context, s, roster)),
            ],
            if (inProgress.isNotEmpty) ...[
              _label(context, 'IN PROGRESS'),
              ...inProgress.map((s) => _tile(context, s, roster)),
            ],
            if (graded.isNotEmpty) ...[
              _label(context, 'GRADED'),
              ...graded.map((s) => _tile(context, s, roster)),
            ],
            if (notStarted.isNotEmpty) ...[
              _label(context, 'NOT STARTED'),
              ...notStarted.map((id) => _notStartedTile(context, roster[id]!)),
            ],
            if (subs.isEmpty && notStarted.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No students are enrolled in this class.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appColors.textSecondary)),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _summary(BuildContext context, int review, int graded, int inProgress,
      int notStarted) {
    Widget stat(String label, int n, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text('$n',
                  style: TextStyle(
                      color: color, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.appColors.textSecondary, fontSize: 11)),
            ]),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(quiz.title,
            style: TextStyle(
                color: context.appColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        Text(
            '${quiz.subject} • ${quiz.classLabel} • ${quiz.totalMarks.toInt()} marks',
            style: TextStyle(
                color: context.appColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          stat('To review', review, AppColors.warning),
          const SizedBox(width: 8),
          stat('Graded', graded, AppColors.success),
          const SizedBox(width: 8),
          stat('In progress', inProgress, AppColors.accentDark),
          const SizedBox(width: 8),
          stat('Not started', notStarted, context.appColors.textMuted),
        ]),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Text(text,
            style: TextStyle(
                color: context.appColors.accentText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
      );

  Widget _tile(
      BuildContext context, QuizSubmission s, Map<String, String> roster) {
    final df = DateFormat('d MMM, h:mm a');
    final name = s.studentName ?? roster[s.studentId] ?? 'Student';
    final (color, icon, status) = switch (s.status) {
      SubmissionStatus.graded => (
          AppColors.success,
          Icons.verified_rounded,
          'Graded'
        ),
      SubmissionStatus.submitted => (
          AppColors.warning,
          Icons.hourglass_bottom_rounded,
          'Awaiting review'
        ),
      SubmissionStatus.inProgress => (
          AppColors.accentDark,
          Icons.edit_note_rounded,
          'In progress'
        ),
    };
    final score = s.finalScore ?? s.autoScore;
    final scoreText = score == null
        ? null
        : s.finalScore != null
            ? '${_fmt(score)} / ${_fmt(quiz.totalMarks)}'
            : 'MCQ ${_fmt(score)} / ${_fmt(s.autoMaxScore ?? 0)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w700)),
        subtitle: Text(
            [
              status,
              if (s.submittedAt != null) df.format(s.submittedAt!),
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        trailing: scoreText == null
            ? Icon(Icons.chevron_right_rounded,
                color: context.appColors.textMuted)
            : Text(scoreText,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w800)),
        onTap: s.isInProgress
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SubmissionReviewScreen(
                        quiz: quiz, submission: s, canGrade: true))),
      ),
    );
  }

  Widget _notStartedTile(BuildContext context, String name) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.appColors.surface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.person_outline_rounded,
              size: 20, color: context.appColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.appColors.textSecondary)),
          ),
          Text('Not started',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ]),
      );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
