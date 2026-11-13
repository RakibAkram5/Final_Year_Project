import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/models/quiz_model.dart';
import '../../../data/models/quiz_submission_model.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import 'submission_review_screen.dart';
import 'take_quiz_screen.dart';

/// Online tests for a student: the ONLINE quizzes of their enrolled classes
/// with the attempt state of each (not started / in progress / submitted /
/// graded). A student taps to attempt or to see their result; a parent
/// ([studentUid] of a linked child) only sees results.
class OnlineTestsScreen extends StatefulWidget {
  /// Whose tests: the signed-in student when null (student portal), or a
  /// linked child's uid (parent portal, read-only).
  final String? studentUid;
  final String? studentName;

  const OnlineTestsScreen({super.key, this.studentUid, this.studentName});

  @override
  State<OnlineTestsScreen> createState() => _OnlineTestsScreenState();
}

class _OnlineTestsScreenState extends State<OnlineTestsScreen> {
  // Attempt state per quiz, loaded lazily per visible quiz.
  final Map<String, Future<QuizSubmission?>> _attempts = {};

  bool get _readOnly => widget.studentUid != null;

  String get _uid =>
      widget.studentUid ?? context.read<AuthProvider>().currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) {
        context.read<ClassProvider>().listenAll(user.academyId ?? '');
      }
    });
  }

  Future<QuizSubmission?> _attemptFor(String quizId) {
    return _attempts.putIfAbsent(
        quizId,
        () => context
            .read<QuizProvider>()
            .getAttempt(quizId, studentId: _readOnly ? _uid : null));
  }

  void _refreshAttempt(String quizId) {
    _attempts.remove(quizId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final title = _readOnly
        ? "${widget.studentName ?? 'Child'}'s Online Tests"
        : 'Online Tests';
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      final user = context.watch<AuthProvider>().currentUser;
      void onDashboard() => Navigator.of(context).popUntil((r) => r.isFirst);
      return WebAppShell(
        title: title,
        titleIcon: Icons.quiz_rounded,
        navSections: user?.role == UserRole.parent
            ? buildParentNavSections(context, onDashboard: onDashboard)
            : buildStudentNavSections(context, onDashboard: onDashboard),
        activeNavId: 'online_tests',
        user: user,
        onLogout: () => performWebLogout(context),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: _body(context))),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(child: SafeArea(child: _body(context))),
    );
  }

  Widget _body(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final academyId = user?.academyId ?? '';
    final uid = _uid;
    return StreamBuilder<List<ClassEntity>>(
      stream: context.read<ClassProvider>().streamForStudent(uid, academyId),
      builder: (context, classSnap) {
        if (classSnap.hasError) return _error(context, classSnap.error);
        final classes = classSnap.data;
        if (classes == null) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        final classIds = classes.map((c) => c.id).toList();
        if (classIds.isEmpty) return _empty(context, enrolled: false);
        return StreamBuilder<List<QuizModel>>(
          stream: context
              .read<QuizProvider>()
              .watchQuizzesForClasses(classIds, academyId),
          builder: (context, quizSnap) {
            if (quizSnap.hasError) return _error(context, quizSnap.error);
            final all = quizSnap.data;
            if (all == null) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent));
            }
            final online = all.where((q) => q.isOnline).toList()
              ..sort((a, b) => b.testDate.compareTo(a.testDate));
            if (online.isEmpty) return _empty(context, enrolled: true);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: online.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _quizTile(context, online[i]),
            );
          },
        );
      },
    );
  }

  Widget _quizTile(BuildContext context, QuizModel quiz) {
    final df = DateFormat('d MMM, h:mm a');
    return FutureBuilder<QuizSubmission?>(
      future: _attemptFor(quiz.id),
      builder: (context, snap) {
        final sub = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        final (label, color, icon) = _statusOf(context, quiz, sub, loading);
        final subtitle = [
          quiz.subject,
          '${quiz.totalMarks.toInt()} marks',
          '${quiz.questions.length} questions',
          if (quiz.durationMinutes != null) '${quiz.durationMinutes} min',
          if (quiz.availableUntil != null)
            'until ${df.format(quiz.availableUntil!)}',
        ].join(' • ');
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: loading ? null : () => _open(context, quiz, sub),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(quiz.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.appColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5)),
                        const SizedBox(height: 3),
                        Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.appColors.textMuted,
                                fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(label,
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (sub?.finalScore != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                  '${sub!.finalScore!.toStringAsFixed(sub.finalScore! == sub.finalScore!.roundToDouble() ? 0 : 1)} / ${quiz.totalMarks.toInt()}',
                                  style: TextStyle(
                                      color: context.appColors.textPrimary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      color: context.appColors.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  (String, Color, IconData) _statusOf(
      BuildContext context, QuizModel quiz, QuizSubmission? sub, bool loading) {
    if (loading) {
      return ('Checking…', context.appColors.textMuted, Icons.quiz_rounded);
    }
    if (sub == null) {
      if (!quiz.isOpenNow) {
        final notYet = quiz.availableFrom != null &&
            DateTime.now().isBefore(quiz.availableFrom!);
        return (
          notYet ? 'Opens later' : 'Closed',
          context.appColors.textMuted,
          Icons.lock_clock_rounded
        );
      }
      return (
        'Not started',
        AppColors.accent,
        Icons.play_circle_outline_rounded
      );
    }
    return switch (sub.status) {
      SubmissionStatus.inProgress => (
          'In progress',
          AppColors.warning,
          Icons.edit_note_rounded
        ),
      SubmissionStatus.submitted => (
          'Awaiting review',
          AppColors.warning,
          Icons.hourglass_bottom_rounded
        ),
      SubmissionStatus.graded => (
          'Graded',
          AppColors.success,
          Icons.verified_rounded
        ),
    };
  }

  Future<void> _open(
      BuildContext context, QuizModel quiz, QuizSubmission? sub) async {
    if (sub != null && sub.isClosed) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SubmissionReviewScreen(
                  quiz: quiz, submission: sub, canGrade: false)));
      return;
    }
    if (_readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sub == null
              ? '${widget.studentName ?? 'Your child'} has not attempted this test yet.'
              : 'This attempt is still in progress.')));
      return;
    }
    if (sub == null && !quiz.isOpenNow) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This test is not open for attempts right now.')));
      return;
    }
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => TakeQuizScreen(quiz: quiz)));
    _refreshAttempt(quiz.id);
  }

  Widget _empty(BuildContext context, {required bool enrolled}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.quiz_outlined,
                size: 64,
                color: context.appColors.textMuted.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(enrolled ? 'No online tests yet' : 'Not enrolled in any class',
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                enrolled
                    ? 'When a teacher publishes a test for online attempt it will appear here.'
                    : 'Ask your academy admin to enrol you in your classes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load tests: $error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger)),
      ),
    );
  }
}
