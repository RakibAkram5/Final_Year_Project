import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/quiz_model.dart';
import '../../../data/models/quiz_submission_model.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../widgets/compact_dialog.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import 'submission_review_screen.dart';

/// Student attempt of an ONLINE quiz.
///
/// Starts (or resumes) the attempt on the server, lets the student move
/// between questions, autosaves answers every few seconds and on every
/// navigation, enforces the server deadline with a visible countdown, and
/// asks for confirmation before the final submit. The submit call is
/// idempotent on the server, so a retry after a dropped connection never
/// creates a duplicate or regrades.
///
/// Correct answers are never available to this screen before submission:
/// the quiz payload for students omits them and the attempt payload only
/// carries correctness after the attempt is closed.
class TakeQuizScreen extends StatefulWidget {
  final QuizModel quiz;
  const TakeQuizScreen({super.key, required this.quiz});

  @override
  State<TakeQuizScreen> createState() => _TakeQuizScreenState();
}

class _TakeQuizScreenState extends State<TakeQuizScreen> {
  QuizSubmission? _submission;
  final Map<String, QuizAnswer> _answers = {};
  final Map<String, TextEditingController> _textCtrls = {};
  final PageController _pager = PageController();

  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  bool _dirty = false;
  String? _error;
  Timer? _autosave;
  Timer? _clock;
  Duration? _remaining;

  List<QuizQuestion> get _questions => widget.quiz.questions;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _clock?.cancel();
    _pager.dispose();
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final sub =
          await context.read<QuizProvider>().startAttempt(widget.quiz.id);
      if (!mounted) return;
      if (sub.isClosed) {
        // Already submitted: show the result instead of the paper.
        _replaceWithReview(sub);
        return;
      }
      for (final a in sub.answers) {
        _answers[a.questionId] = a;
      }
      for (final q in _questions) {
        _textCtrls[q.id] =
            TextEditingController(text: _answers[q.id]?.answerText ?? '');
      }
      setState(() {
        _submission = sub;
        _loading = false;
      });
      _autosave = Timer.periodic(const Duration(seconds: 20), (_) => _save());
      if (sub.deadline != null) {
        _tick();
        _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _replaceWithReview(QuizSubmission sub) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SubmissionReviewScreen(
            quiz: widget.quiz, submission: sub, canGrade: false)));
  }

  void _tick() {
    final deadline = _submission?.deadline;
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) {
      _clock?.cancel();
      setState(() => _remaining = Duration.zero);
      // Time is up: submit whatever has been answered.
      _submit(force: true);
      return;
    }
    setState(() => _remaining = left);
  }

  void _setAnswer(QuizQuestion q, {int? selectedIndex, String? text}) {
    final current = _answers[q.id] ?? QuizAnswer(questionId: q.id);
    _answers[q.id] = current.copyWith(
      selectedIndex: selectedIndex,
      answerText: text,
    );
    _dirty = true;
    setState(() {});
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _submitting || _submission == null) return;
    _saving = true;
    _dirty = false;
    try {
      await context
          .read<QuizProvider>()
          .saveAnswers(widget.quiz.id, _answers.values.toList());
    } catch (_) {
      // Transient failure: keep the answers locally and retry on the next
      // autosave tick or at submission time.
      _dirty = true;
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _submit({bool force = false}) async {
    if (_submitting || _submission == null) return;
    if (!force) {
      final unanswered = _questions
          .where((q) => !(_answers[q.id]?.isAnswered ?? false))
          .length;
      final ok = await showCompactDialog<bool>(
        context: context,
        title: 'Submit test?',
        icon: Icons.task_alt_rounded,
        content: Builder(
          builder: (ctx) => Text(
            unanswered == 0
                ? 'All ${_questions.length} questions are answered. Once submitted you cannot change your answers.'
                : '$unanswered of ${_questions.length} questions are still unanswered. Once submitted you cannot change your answers.',
            style: TextStyle(color: ctx.appColors.textSecondary),
          ),
        ),
        actions: [
          Builder(
              builder: (ctx) => TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep working'))),
          Builder(
              builder: (ctx) => FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Submit'))),
        ],
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _submitting = true);
    _autosave?.cancel();
    final provider = context.read<QuizProvider>();
    try {
      final sub = await provider.submitAttempt(
          widget.quiz.id, _answers.values.toList());
      if (!mounted) return;
      _clock?.cancel();
      _replaceWithReview(sub);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Could not submit: $e. Your answers are kept; '
              'check your connection and try again.')));
      if (!force) {
        _autosave = Timer.periodic(const Duration(seconds: 20), (_) => _save());
      }
    }
  }

  void _goTo(int i) {
    if (i < 0 || i >= _questions.length) return;
    _save();
    setState(() => _index = i);
    _pager.animateToPage(i,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<bool> _confirmLeave() async {
    if (_submission == null || _submission!.isClosed) return true;
    await _save();
    if (!mounted) return true;
    final leave = await showCompactDialog<bool>(
      context: context,
      title: 'Leave the test?',
      icon: Icons.pause_circle_outline_rounded,
      content: Text(
        _remaining == null
            ? 'Your answers are saved. You can come back and continue this attempt later.'
            : 'Your answers are saved, but the timer keeps running while you are away.',
        style: TextStyle(color: context.appColors.textSecondary),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave')),
      ],
    );
    return leave == true;
  }

  Future<void> _popIfConfirmed() async {
    final navigator = Navigator.of(context);
    if (await _confirmLeave()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => _popIfConfirmed(),
        child: WebAppShell(
          title: widget.quiz.title,
          titleIcon: Icons.quiz_rounded,
          navSections: buildStudentNavSections(context, onDashboard: () async {
            final navigator = Navigator.of(context);
            if (await _confirmLeave()) navigator.popUntil((r) => r.isFirst);
          }),
          activeNavId: 'online_tests',
          user: context.watch<AuthProvider>().currentUser,
          onLogout: () => performWebLogout(context),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: body)),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _popIfConfirmed(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.quiz.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [if (_remaining != null) _timerChip(context)],
        ),
        body: GradientBackground(child: SafeArea(child: body)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_rounded,
                  size: 56, color: AppColors.warning),
              const SizedBox(height: 16),
              Text('This test cannot be started',
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.textSecondary)),
              const SizedBox(height: 20),
              OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back')),
            ],
          ),
        ),
      );
    }
    if (_questions.isEmpty) {
      return Center(
          child: Text('This test has no questions yet.',
              style: TextStyle(color: context.appColors.textSecondary)));
    }
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    return Column(
      children: [
        _header(context, isWide),
        Expanded(
          child: PageView.builder(
            controller: _pager,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _questions.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _questionCard(context, _questions[i], i),
          ),
        ),
        _footer(context),
      ],
    );
  }

  Widget _timerChip(BuildContext context) {
    final r = _remaining!;
    final urgent = r.inMinutes < 5;
    final text =
        '${r.inHours > 0 ? '${r.inHours}:' : ''}${(r.inMinutes % 60).toString().padLeft(2, '0')}:${(r.inSeconds % 60).toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (urgent ? AppColors.danger : AppColors.accent)
            .withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined,
            size: 16,
            color: urgent ? AppColors.danger : context.appColors.accentText),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
                color:
                    urgent ? AppColors.danger : context.appColors.accentText)),
      ]),
    );
  }

  Widget _header(BuildContext context, bool isWide) {
    final answered =
        _questions.where((q) => _answers[q.id]?.isAnswered ?? false).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    '${widget.quiz.subject} • ${widget.quiz.totalMarks.toInt()} marks • $answered/${_questions.length} answered',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.appColors.textSecondary, fontSize: 13)),
              ),
              if (isWide && _remaining != null) _timerChip(context),
              _saveIndicator(context),
            ],
          ),
          const SizedBox(height: 10),
          // Question navigator: one chip per question, coloured by state.
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _questions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final q = _questions[i];
                final done = _answers[q.id]?.isAnswered ?? false;
                final active = i == _index;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _goTo(i),
                  child: Container(
                    width: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? AppColors.accent
                          : done
                              ? AppColors.success.withValues(alpha: 0.18)
                              : context.appColors.surface,
                      border: Border.all(
                          color: active
                              ? AppColors.accent
                              : done
                                  ? AppColors.success
                                  : context.appColors.border),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: active
                                ? AppColors.textOnAccent
                                : context.appColors.textPrimary)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveIndicator(BuildContext context) {
    final label = _saving ? 'Saving…' : (_dirty ? 'Unsaved' : 'Saved');
    final color = _saving
        ? context.appColors.textMuted
        : (_dirty ? AppColors.warning : AppColors.success);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_saving ? Icons.sync_rounded : Icons.cloud_done_rounded,
            size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ]),
    );
  }

  Widget _questionCard(BuildContext context, QuizQuestion q, int i) {
    final answer = _answers[q.id];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.appColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Question ${i + 1} of ${_questions.length}',
                    style: TextStyle(
                        color: context.appColors.accentText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      '${q.marks == q.marks.roundToDouble() ? q.marks.toInt() : q.marks} mark${q.marks == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: context.appColors.accentText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(q.text,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 17,
                    height: 1.4,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            if (q.type == QuestionType.mcq && (q.options?.isNotEmpty ?? false))
              ...List.generate(q.options!.length, (oi) {
                final selected = answer?.selectedIndex == oi;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _setAnswer(q, selectedIndex: oi),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accent.withValues(alpha: 0.14)
                            : context.appColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: selected
                                ? AppColors.accent
                                : context.appColors.border,
                            width: selected ? 1.6 : 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? AppColors.accent
                                  : context.appColors.surface,
                              border: Border.all(
                                  color: selected
                                      ? AppColors.accent
                                      : context.appColors.border),
                            ),
                            child: Text(String.fromCharCode(65 + oi),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? AppColors.textOnAccent
                                        : context.appColors.textSecondary)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(q.options![oi],
                                style: TextStyle(
                                    color: context.appColors.textPrimary,
                                    fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })
            else
              TextField(
                controller: _textCtrls[q.id],
                maxLines: q.type == QuestionType.long ? 10 : 4,
                minLines: q.type == QuestionType.long ? 6 : 3,
                onChanged: (v) => _setAnswer(q, text: v),
                style: TextStyle(color: context.appColors.textPrimary),
                decoration: InputDecoration(
                  hintText: q.type == QuestionType.long
                      ? 'Write your detailed answer here…'
                      : 'Write a short answer…',
                  alignLabelWithHint: true,
                ),
              ),
            if (q.type == QuestionType.mcq && answer?.selectedIndex != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    _answers[q.id] = answer!.copyWith(clearSelectedIndex: true);
                    _dirty = true;
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Clear choice'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final last = _index == _questions.length - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        // Two flexible buttons so the row never overflows on 320 px phones
        // or at large accessibility text sizes.
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _index == 0 ? null : () => _goTo(_index - 1),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                label: const Text('Previous',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: !last
                  ? FilledButton.icon(
                      onPressed: () => _goTo(_index + 1),
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      label: const Text('Next',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    )
                  : FilledButton.icon(
                      onPressed: _submitting ? null : () => _submit(),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: AppColors.textOnAccent),
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.task_alt_rounded, size: 20),
                      label: Text(_submitting ? 'Submitting…' : 'Submit',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
