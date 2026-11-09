import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/models/class_entity.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/class_report_pdf.dart';
import '../../data/remote/quiz_service.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/class_repository.dart';
import '../../logic/auth_provider.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/responsive/responsive_row.dart';
import 'file_viewer_screen.dart';

/// Downloadable reports for admins and teachers: class attendance (daily or
/// any range) and class results as PDF or Excel, and academy fee records as
/// Excel (admin only). Excel files are built by the server from live data;
/// PDFs are generated on the device from the same API responses.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _ymd = DateFormat('yyyy-MM-dd');
  late final Future<List<ClassEntity>> _classes;
  ClassEntity? _class;
  DateTimeRange _range = DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime.now());
  String _feePeriod = DateFormat('yyyy-MM').format(DateTime.now());
  String? _busy;

  bool get _isAdmin =>
      context.read<AuthProvider>().currentUser?.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    final repo = ClassRepository();
    _classes = user?.role == UserRole.teacher
        ? repo.watchForTeacher(user!.uid, user.academyId ?? '').first
        : repo.watchAll(user?.academyId ?? '').first;
  }

  Future<void> _run(String key, Future<void> Function() job) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Report failed: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _deliver(Uint8List bytes, String name, String mime) async {
    if (!mounted) return;
    await saveOrShareBytes(context, bytes, name, mime);
  }

  String get _academy =>
      context.read<AuthProvider>().currentUser?.academyName ?? 'Academy';

  Future<void> _attendancePdf() => _run('att-pdf', () async {
        final c = _class!;
        final records = await AttendanceRepository().getAllForAcademy('',
            classId: c.id, from: _range.start, to: _range.end);
        final bytes = await ClassReportPdf.attendance(
            academyName: _academy,
            cls: c,
            records: records,
            from: _range.start,
            to: _range.end);
        await _deliver(
            bytes,
            'attendance_${c.className}_${_ymd.format(_range.start)}_${_ymd.format(_range.end)}.pdf',
            'application/pdf');
      });

  Future<void> _resultsPdf() => _run('res-pdf', () async {
        final c = _class!;
        final quizService = QuizService();
        final marks = await quizService.watchClassMarks(c.id, '').first;
        final quizzes =
            await quizService.watchQuizzesForClasses([c.id], '').first;
        final bytes = await ClassReportPdf.results(
            academyName: _academy,
            cls: c,
            marks: marks,
            quizTitles: {for (final q in quizzes) q.id: q.title});
        await _deliver(bytes, 'results_${c.className}.pdf', 'application/pdf');
      });

  static const _xlsx =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Future<void> _excel(String key, String path, String name) =>
      _run(key, () async {
        final bytes = await ApiClient().getBytes(path);
        await _deliver(bytes, name, _xlsx);
      });

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (r != null) setState(() => _range = r);
  }

  Widget _action(String key, IconData icon, String label, VoidCallback? onTap) {
    final busy = _busy == key;
    return OutlinedButton.icon(
      onPressed: _busy == null ? onTap : null,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent))
          : Icon(icon),
      label: Text(label, textAlign: TextAlign.center),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: const BorderSide(color: AppColors.accent),
        padding: const EdgeInsets.all(14),
      ),
    );
  }

  Widget _section(String title, String help, List<Widget> children) {
    final colors = context.appColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 4),
            Text(help,
                style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noClass = _class == null;
    final range = _range.start == _range.end
        ? DateFormat('d MMM yyyy').format(_range.start)
        : '${DateFormat('d MMM').format(_range.start)} – ${DateFormat('d MMM yyyy').format(_range.end)}';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Reports & exports',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
                  FutureBuilder<List<ClassEntity>>(
                    future: _classes,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Text('Could not load classes: ${snap.error}',
                            style: const TextStyle(color: AppColors.danger));
                      }
                      if (!snap.hasData) {
                        return const LinearProgressIndicator(
                            color: AppColors.accent);
                      }
                      return DropdownButtonFormField<ClassEntity>(
                        initialValue: _class,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Class'),
                        hint: Text(snap.data!.isEmpty
                            ? 'No classes available'
                            : 'Choose a class'),
                        items: snap.data!
                            .map((c) => DropdownMenuItem(
                                value: c, child: DropdownLabel(c.displayLabel)))
                            .toList(),
                        onChanged: (c) => setState(() => _class = c),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _section(
                      'Attendance',
                      'Per-student present/late/leave/absent and attendance % '
                          'for a single day or any range (e.g. a month).',
                      [
                        OutlinedButton.icon(
                          onPressed: _pickRange,
                          icon: const Icon(Icons.date_range_rounded),
                          label: Text(range),
                        ),
                        const SizedBox(height: 10),
                        ResponsiveRow(breakpoint: 420, children: [
                          _action('att-pdf', Icons.picture_as_pdf_rounded,
                              'PDF', noClass ? null : _attendancePdf),
                          _action(
                              'att-xlsx',
                              Icons.table_chart_rounded,
                              'Excel',
                              noClass
                                  ? null
                                  : () => _excel(
                                      'att-xlsx',
                                      '/reports/attendance.xlsx?classId=${_class!.id}'
                                          '&from=${_ymd.format(_range.start)}&to=${_ymd.format(_range.end)}',
                                      'attendance_${_class!.className}.xlsx')),
                        ]),
                      ]),
                  const SizedBox(height: 12),
                  _section(
                      'Results',
                      'Every test of the class with marks, percentage and '
                          'grade, plus each student\'s overall percentage.',
                      [
                        ResponsiveRow(breakpoint: 420, children: [
                          _action('res-pdf', Icons.picture_as_pdf_rounded,
                              'PDF', noClass ? null : _resultsPdf),
                          _action(
                              'res-xlsx',
                              Icons.table_chart_rounded,
                              'Excel',
                              noClass
                                  ? null
                                  : () => _excel(
                                      'res-xlsx',
                                      '/reports/results.xlsx?classId=${_class!.id}',
                                      'results_${_class!.className}.xlsx')),
                        ]),
                      ]),
                  if (_isAdmin) ...[
                    const SizedBox(height: 12),
                    _section(
                        'Fee records',
                        'All challans for a billing month with status and '
                            'payment date.',
                        [
                          TextFormField(
                            initialValue: _feePeriod,
                            decoration: const InputDecoration(
                                labelText: 'Billing month (YYYY-MM)'),
                            onChanged: (v) => _feePeriod = v.trim(),
                          ),
                          const SizedBox(height: 10),
                          _action(
                              'fee-xlsx',
                              Icons.table_chart_rounded,
                              'Excel',
                              () => RegExp(r'^\d{4}-\d{2}$')
                                      .hasMatch(_feePeriod)
                                  ? _excel(
                                      'fee-xlsx',
                                      '/reports/fees.xlsx?period=$_feePeriod',
                                      'fees_$_feePeriod.xlsx')
                                  : ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Enter the month as YYYY-MM.')))),
                        ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
