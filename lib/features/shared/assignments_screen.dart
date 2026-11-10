import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/models/class_entity.dart';
import '../../data/remote/assignment_service.dart';
import '../../data/remote/file_service.dart';
import '../../data/repositories/class_repository.dart';
import '../../logic/auth_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/attachments_section.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/responsive/responsive_row.dart';

final _due = DateFormat('EEE d MMM yyyy, h:mm a');

/// Assignments for the signed-in user. Teachers/admins create and grade;
/// students submit; parents (optionally for one [childId]) follow progress.
/// The list is scoped by the server to the caller's classes.
class AssignmentsScreen extends StatefulWidget {
  final String? childId;
  final String? childName;
  const AssignmentsScreen({super.key, this.childId, this.childName});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  final _service = AssignmentService();
  late final Stream<List<Assignment>> _stream = _service.watch();

  bool get _isStaff {
    final role = context.read<AuthProvider>().currentUser?.role;
    return role == UserRole.teacher || role == UserRole.admin;
  }

  Future<void> _create() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CreateAssignmentSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final staff = _isStaff;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
            widget.childName == null
                ? 'Assignments'
                : '${widget.childName} · Assignments',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: staff
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textOnAccent,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New assignment'),
              onPressed: _create,
            )
          : null,
      body: GradientBackground(
        child: SafeArea(
          child: StreamBuilder<List<Assignment>>(
            stream: _stream,
            builder: (context, snap) {
              if (!snap.hasData && !snap.hasError) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent));
              }
              if (snap.hasError && !snap.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load assignments.\n${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger)),
                  ),
                );
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        staff
                            ? 'No assignments yet. Tap "New assignment" to create one.'
                            : 'No assignments have been given yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary)),
                  ),
                );
              }
              return ListView.separated(
                // Bottom padding keeps the last card clear of the FAB.
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _card(list[i], staff),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _card(Assignment a, bool staff) {
    final colors = context.appColors;
    final me = context.read<AuthProvider>().currentUser;
    final studentId = widget.childId ?? me?.uid ?? '';
    final sub = staff ? null : a.submissionFor(studentId);
    final chips = <Widget>[
      if (staff)
        _statusChip('${a.submissionCount ?? 0} submitted', AppColors.accent)
      else if (sub?.isGraded == true)
        _statusChip(
            'Graded ${_fmt(sub!.marks!)}${a.maxMarks == null ? '' : '/${a.maxMarks}'}',
            AppColors.success)
      else if (sub?.hasFiles == true)
        _statusChip('Submitted', AppColors.success)
      else if (a.isOpen)
        _statusChip('Pending', AppColors.warning)
      else
        _statusChip('Missed', AppColors.danger),
      _statusChip(a.isOpen ? 'Open' : 'Closed',
          a.isOpen ? AppColors.accent : colors.textMuted),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AssignmentDetailScreen(
                    assignment: a, staff: staff, studentId: studentId))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(a.classLabel,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Due ${_due.format(a.dueAt)}',
                  style: TextStyle(color: colors.textMuted, fontSize: 12)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: chips),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Assignment details. Staff see instruction files (editable) and all
/// submissions with grading; students see instructions and manage their own
/// submission until the deadline; parents see their child's submission.
class AssignmentDetailScreen extends StatefulWidget {
  final Assignment assignment;
  final bool staff;
  final String studentId;
  const AssignmentDetailScreen(
      {super.key,
      required this.assignment,
      required this.staff,
      required this.studentId});

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  final _service = AssignmentService();
  final _note = TextEditingController();
  String? _submissionId;
  bool _busy = false;
  Future<(int, List<AssignmentSubmission>)>? _subs;

  Assignment get a => widget.assignment;

  bool get _isStudent =>
      context.read<AuthProvider>().currentUser?.role == UserRole.student;

  @override
  void initState() {
    super.initState();
    final mine = a.submissionFor(widget.studentId);
    _submissionId = mine?.id;
    _note.text = mine?.note ?? '';
    if (widget.staff) _subs = _service.submissions(a.id);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: error ? AppColors.danger : AppColors.success));
  }

  Future<void> _startOrUpdateSubmission() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await _service.submit(a.id, note: _note.text.trim());
      setState(() => _submissionId = id);
      _toast('Submission saved. Attach your file below.');
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete assignment?'),
        content: const Text(
            'All submissions and files for this assignment will be removed.'),
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
    if (ok != true) return;
    try {
      await _service.delete(a.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('$e', error: true);
    }
  }

  Future<void> _grade(AssignmentSubmission s) async {
    final graded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _GradeSheet(assignment: a, submission: s),
    );
    if (graded == true) {
      setState(() => _subs = _service.submissions(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(a.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (widget.staff)
            IconButton(
                tooltip: 'Delete assignment',
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: _delete),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(a.classLabel,
                      style: TextStyle(color: colors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                      'Due ${_due.format(a.dueAt)}'
                      '${a.maxMarks == null ? '' : ' · ${a.maxMarks} marks'}'
                      '${a.allowResubmission ? '' : ' · single submission'}',
                      style: TextStyle(
                          color: a.isOpen
                              ? context.appColors.accentText
                              : AppColors.danger,
                          fontWeight: FontWeight.w600)),
                  if ((a.instructions ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(a.instructions!,
                        style: TextStyle(color: colors.textPrimary)),
                  ],
                  const SizedBox(height: 16),
                  AttachmentsSection(
                    category: FileCategory.assignmentInstruction,
                    ownerId: a.id,
                    canEdit: widget.staff,
                    title: 'Instructions',
                    emptyText: 'No instruction files.',
                  ),
                  const Divider(height: 32),
                  if (widget.staff) _submissionsList() else _mySubmission(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mySubmission() {
    final colors = context.appColors;
    final mine = a.submissionFor(widget.studentId);
    final canWork = _isStudent && a.isOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_isStudent ? 'MY SUBMISSION' : 'SUBMISSION',
            style: TextStyle(
                color: colors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1)),
        const SizedBox(height: 8),
        if (mine?.isGraded == true)
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.grade_rounded, color: AppColors.success),
              title: Text(
                  'Marks: ${_fmt(mine!.marks!)}${a.maxMarks == null ? '' : ' / ${a.maxMarks}'}'),
              subtitle: (mine.feedback ?? '').isEmpty
                  ? null
                  : Text('Feedback: ${mine.feedback}'),
            ),
          ),
        if (canWork) ...[
          LabeledField(
              label: 'Note to teacher (optional)',
              hint: 'Anything your teacher should know',
              controller: _note),
          PrimaryButton(
            label: _submissionId == null ? 'Start submission' : 'Save note',
            icon: Icons.send_rounded,
            loading: _busy,
            onPressed: _busy ? null : _startOrUpdateSubmission,
          ),
          const SizedBox(height: 16),
        ] else if (_submissionId == null)
          Text(
              a.isOpen
                  ? 'Nothing submitted yet.'
                  : 'The deadline has passed. Nothing was submitted.',
              style: TextStyle(color: colors.textSecondary)),
        if (_submissionId != null)
          AttachmentsSection(
            category: FileCategory.assignmentSubmission,
            ownerId: _submissionId!,
            canEdit: canWork,
            title: 'Submitted files',
            emptyText: canWork
                ? 'Upload your work (PDF, Word or image, max 4 MB).'
                : 'No files submitted.',
          ),
      ],
    );
  }

  Widget _submissionsList() {
    final colors = context.appColors;
    return FutureBuilder<(int, List<AssignmentSubmission>)>(
      future: _subs,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snap.hasError) {
          return Text('Could not load submissions: ${snap.error}',
              style: const TextStyle(color: AppColors.danger));
        }
        final (enrolled, subs) = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SUBMISSIONS (${subs.length} of $enrolled students)',
                style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
            const SizedBox(height: 8),
            if (subs.isEmpty)
              Text('No submissions yet.',
                  style: TextStyle(color: colors.textSecondary)),
            for (final s in subs)
              Card(
                child: ListTile(
                  onTap: () => _grade(s),
                  title: Text(s.studentName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${DateFormat('d MMM, h:mm a').format(s.submittedAt)}'
                      ' · ${s.fileCount} file${s.fileCount == 1 ? '' : 's'}'
                      '${s.late ? ' · LATE' : ''}'),
                  trailing: Text(
                      s.isGraded
                          ? '${_fmt(s.marks!)}${a.maxMarks == null ? '' : '/${a.maxMarks}'}'
                          : 'Grade',
                      style: TextStyle(
                          color: s.isGraded
                              ? AppColors.success
                              : context.appColors.accentText,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GradeSheet extends StatefulWidget {
  final Assignment assignment;
  final AssignmentSubmission submission;
  const _GradeSheet({required this.assignment, required this.submission});

  @override
  State<_GradeSheet> createState() => _GradeSheetState();
}

class _GradeSheetState extends State<_GradeSheet> {
  late final _marks = TextEditingController(
      text: widget.submission.marks == null
          ? ''
          : _fmt(widget.submission.marks!));
  late final _feedback =
      TextEditingController(text: widget.submission.feedback ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _marks.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_marks.text.trim());
    final max = widget.assignment.maxMarks;
    if (value == null || value < 0) {
      setState(() => _error = 'Enter marks as a number of 0 or more.');
      return;
    }
    if (max != null && value > max) {
      setState(() => _error = 'Marks cannot exceed $max.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AssignmentService().grade(
          widget.assignment.id, widget.submission.id,
          marks: value, feedback: _feedback.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.studentName,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if ((s.note ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Note: ${s.note}'),
            ],
            const SizedBox(height: 12),
            AttachmentsSection(
              category: FileCategory.assignmentSubmission,
              ownerId: s.id,
              title: 'Submitted files',
              emptyText: 'No files were attached.',
            ),
            const SizedBox(height: 16),
            LabeledField(
                label: widget.assignment.maxMarks == null
                    ? 'Marks'
                    : 'Marks (out of ${widget.assignment.maxMarks})',
                hint: 'e.g. 15',
                controller: _marks,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
            LabeledField(
                label: 'Feedback (optional)',
                hint: 'Comments for the student',
                controller: _feedback),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger)),
              ),
            PrimaryButton(
                label: 'Save grade',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}

class _CreateAssignmentSheet extends StatefulWidget {
  const _CreateAssignmentSheet();

  @override
  State<_CreateAssignmentSheet> createState() => _CreateAssignmentSheetState();
}

class _CreateAssignmentSheetState extends State<_CreateAssignmentSheet> {
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  final _maxMarks = TextEditingController();
  late final Future<List<ClassEntity>> _classes;
  ClassEntity? _class;
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  bool _allowResubmission = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    final repo = ClassRepository();
    // The server already scopes /classes to the teacher's own classes.
    _classes = user?.role == UserRole.teacher
        ? repo.watchForTeacher(user!.uid, user.academyId ?? '').first
        : repo.watchAll(user?.academyId ?? '').first;
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _maxMarks.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (time == null) return;
    setState(() => _due =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final max = _maxMarks.text.trim().isEmpty
        ? null
        : int.tryParse(_maxMarks.text.trim());
    if (_class == null) {
      setState(() => _error = 'Choose a class.');
      return;
    }
    if (_title.text.trim().length < 2) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    if (_maxMarks.text.trim().isNotEmpty && (max == null || max < 1)) {
      setState(() => _error = 'Maximum marks must be a whole number above 0.');
      return;
    }
    if (!_due.isAfter(DateTime.now())) {
      setState(() => _error = 'The deadline must be in the future.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AssignmentService().create(
        classId: _class!.id,
        title: _title.text,
        instructions: _instructions.text,
        dueAt: _due,
        maxMarks: max,
        allowResubmission: _allowResubmission,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Assignment created. Open it to attach instruction files.'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New assignment',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            FutureBuilder<List<ClassEntity>>(
              future: _classes,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return snap.hasError
                      ? Text('Could not load classes: ${snap.error}',
                          style: const TextStyle(color: AppColors.danger))
                      : const LinearProgressIndicator(color: AppColors.accent);
                }
                if (snap.data!.isEmpty) {
                  return Text('You have no classes to assign work to.',
                      style: TextStyle(color: colors.textSecondary));
                }
                return DropdownButtonFormField<ClassEntity>(
                  initialValue: _class,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Class'),
                  items: snap.data!
                      .map((c) => DropdownMenuItem(
                          value: c, child: DropdownLabel(c.displayLabel)))
                      .toList(),
                  onChanged: (c) => setState(() => _class = c),
                );
              },
            ),
            const SizedBox(height: 12),
            LabeledField(
                label: 'Title',
                hint: 'e.g. Essay on climate',
                controller: _title),
            LabeledField(
                label: 'Instructions (optional)',
                hint: 'What should students do?',
                controller: _instructions),
            ResponsiveRow(children: [
              OutlinedButton.icon(
                onPressed: _pickDue,
                icon: const Icon(Icons.event_rounded),
                label: Text('Due ${_due.day}/${_due.month}/${_due.year} '
                    '${TimeOfDay.fromDateTime(_due).format(context)}'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    padding: const EdgeInsets.all(14)),
              ),
              LabeledField(
                  label: 'Max marks (optional)',
                  hint: 'e.g. 20',
                  controller: _maxMarks,
                  keyboardType: TextInputType.number),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allowResubmission,
              activeThumbColor: AppColors.accent,
              title: const Text('Allow replacing before the deadline'),
              onChanged: (v) => setState(() => _allowResubmission = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger)),
              ),
            PrimaryButton(
                label: 'Create assignment',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
