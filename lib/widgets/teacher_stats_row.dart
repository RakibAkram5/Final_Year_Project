import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../data/models/timetable_slot.dart';
import '../data/repositories/attendance_repository.dart';
import '../features/ocr/services/ocr_firestore_service.dart';
import '../logic/class_provider.dart';
import '../logic/timetable_provider.dart';
import 'dashboard_stat_card.dart';

/// "At a glance" row for the Teacher dashboard — Today's Classes, Today's
/// Attendance, Assigned Subjects, OCR Documents. All four are read from
/// already-existing providers/services (ClassProvider, TimetableProvider,
/// AttendanceRepository, OcrFirestoreService); nothing new is written here.
class TeacherStatsRow extends StatefulWidget {
  final String teacherUid;
  final String academyId;

  const TeacherStatsRow(
      {super.key, required this.teacherUid, required this.academyId});

  @override
  State<TeacherStatsRow> createState() => _TeacherStatsRowState();
}

class _TeacherStatsRowState extends State<TeacherStatsRow> {
  final _attendanceRepo = AttendanceRepository();
  late final Future<int> _markedTodayFuture;

  @override
  void initState() {
    super.initState();
    // Never notify a provider while the widget tree is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ClassProvider>().listenAll(widget.academyId);
    });
    _markedTodayFuture = _countMarkedToday();
  }

  /// Records marked today in this teacher's classes. The server already
  /// limits a teacher's attendance query to the classes they teach, so this
  /// does not depend on the class list having loaded yet.
  Future<int> _countMarkedToday() async {
    final today = DateTime.now();
    final records = await _attendanceRepo.getAllForAcademy(widget.academyId,
        from: today, to: today);
    return records.length;
  }

  @override
  Widget build(BuildContext context) {
    final classes = context
        .watch<ClassProvider>()
        .classes
        .where((c) => c.primaryTeacherId == widget.teacherUid)
        .toList();
    final subjectCount =
        classes.map((c) => c.subject).where((s) => s.isNotEmpty).toSet().length;

    return Row(
      children: [
        Expanded(
          child: StreamBuilder<List<TimetableSlot>>(
            stream: context
                .read<TimetableProvider>()
                .watchForTeacher(widget.teacherUid, widget.academyId),
            builder: (context, snap) {
              final todayWeekday = DateTime.now().weekday;
              final count = (snap.data ?? const [])
                  .where((s) => s.dayOfWeek == todayWeekday && !s.isBreak)
                  .length;
              return DashboardStatCard(
                  label: "Today's Classes",
                  value: snap.hasData ? '$count' : '--',
                  icon: Icons.today_rounded,
                  color: AppColors.accent);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FutureBuilder<int>(
            future: _markedTodayFuture,
            builder: (context, snap) => DashboardStatCard(
                label: 'Marked Today',
                value: snap.hasData ? '${snap.data}' : '--',
                icon: Icons.fact_check_rounded,
                color: AppColors.success),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DashboardStatCard(
              label: 'Subjects',
              value: '$subjectCount',
              icon: Icons.menu_book_rounded,
              color: AppColors.accentDark),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder(
            stream: OcrFirestoreService().getDocuments(widget.teacherUid),
            builder: (context, snap) => DashboardStatCard(
                label: 'OCR Docs',
                value: snap.hasData ? '${(snap.data as List).length}' : '--',
                icon: Icons.document_scanner_rounded,
                color: AppColors.warning),
          ),
        ),
      ],
    );
  }
}
