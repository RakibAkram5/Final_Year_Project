import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/attendance_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/remote/academic_report_pdf_service.dart';

class StudentAttendanceScreen extends StatelessWidget {
  final String studentUid;
  const StudentAttendanceScreen({super.key, required this.studentUid});

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
        title: const Text('My Attendance',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(context),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildStudentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'My Attendance',
      titleIcon: Icons.fact_check_rounded,
      navSections: navSections,
      activeNavId: 'my_attendance',
      user: Provider.of<AuthProvider>(context).currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final academyId = user?.academyId ?? '';

    return academyId.isEmpty
        ? const Center(child: Text("Academy session error"))
        : StreamBuilder<List<ClassEntity>>(
            stream: context
                .read<ClassProvider>()
                .streamForStudent(studentUid, academyId),
            builder: (context, courseSnap) {
              final courses = courseSnap.data ?? const [];
              return StreamBuilder<List<AttendanceRecord>>(
                stream: context
                    .read<AttendanceProvider>()
                    .watchStudentAttendance(studentUid, academyId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      courseSnap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.accent));
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.danger, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              "Error loading records: ${snapshot.error}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "If you see an 'index' error, please wait a minute for Firestore to auto-generate it or check your rules.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: context.appColors.textMuted,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final records = snapshot.data ?? [];

                  if (records.isEmpty && courses.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  return Column(
                    children: [
                      _buildStatsHeader(context, records),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: records.isEmpty || user == null
                                ? null
                                : () async {
                                    try {
                                      await AcademicReportPdfService.attendance(
                                        student: user,
                                        records: records,
                                        classes: courses,
                                      );
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(
                                              'Could not create report: $error'),
                                        ));
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.picture_as_pdf_rounded),
                            label: const Text('Print attendance report'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildDateGroupedView(context, courses, records),
                      ),
                    ],
                  );
                },
              );
            },
          );
  }

  Widget _buildStatsHeader(
      BuildContext context, List<AttendanceRecord> records) {
    final total = records.length;
    final present = records.where((r) => r.status == 'present').length;
    final late = records.where((r) => r.status == 'late').length;
    final absent = records.where((r) => r.status == 'absent').length;
    final leave = records.where((r) => r.status == 'leave').length;
    final percentage = total == 0 ? 0 : ((present + late) / total) * 100;

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(context, "Overall", "${percentage.toStringAsFixed(1)}%",
              AppColors.accent),
          _statItem(context, "Present", "$present", AppColors.success),
          _statItem(context, "Absent", "$absent", AppColors.danger),
          _statItem(context, "Leave", "$leave", AppColors.accent),
        ],
      ),
    );
  }

  Widget _statItem(
      BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  /// Groups attendance records by day (newest first), showing every subject
  /// attended that day with its status — so "how many lectures did I attend
  /// today" is answerable at a glance, matching how parents/students think
  /// about a day's attendance rather than one subject's history at a time.
  Widget _buildDateGroupedView(BuildContext context, List<ClassEntity> courses,
      List<AttendanceRecord> records) {
    if (records.isEmpty) return _buildEmptyState(context);

    final courseById = {for (final c in courses) c.id: c};
    final Map<String, List<AttendanceRecord>> byDate = {};
    for (final r in records) {
      byDate
          .putIfAbsent(DateFormat('yyyy-MM-dd').format(r.logDate), () => [])
          .add(r);
    }
    final dateKeys = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      itemCount: dateKeys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) =>
          _dayCard(context, dateKeys[i], byDate[dateKeys[i]]!, courseById),
    );
  }

  Widget _dayCard(BuildContext context, String dateKey,
      List<AttendanceRecord> records, Map<String, ClassEntity> courseById) {
    final date = DateFormat('yyyy-MM-dd').parse(dateKey);
    final present = records.where((r) => r.isPresent).length;
    final late = records.where((r) => r.isLate).length;
    final total = records.length;
    final pct = total == 0 ? 0.0 : ((present + late) / total) * 100;

    // Alphabetical by subject so the same day reads consistently every time.
    final sorted = [...records]..sort((a, b) {
        final aLabel = courseById[a.classId]?.subject ?? a.classId;
        final bLabel = courseById[b.classId]?.subject ?? b.classId;
        return aLabel.compareTo(bLabel);
      });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('EEEE, d MMMM yyyy').format(date),
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              Text('${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: pct >= 75 ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          ...sorted.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _subjectRow(context, r, courseById[r.classId]),
              )),
        ],
      ),
    );
  }

  Widget _subjectRow(
      BuildContext context, AttendanceRecord r, ClassEntity? course) {
    Color statusColor;
    IconData icon;
    switch (r.status) {
      case 'present':
        statusColor = AppColors.success;
        icon = Icons.check_circle_rounded;
        break;
      case 'late':
        statusColor = AppColors.warning;
        icon = Icons.access_time_filled_rounded;
        break;
      case 'leave':
        statusColor = AppColors.accent;
        icon = Icons.event_busy_rounded;
        break;
      default:
        statusColor = AppColors.danger;
        icon = Icons.cancel_rounded;
    }
    final label = course?.subject.isNotEmpty == true
        ? course!.subject
        : (course?.displayLabel ?? 'Unknown Subject');

    return Row(
      children: [
        Icon(icon, color: statusColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w500)),
        ),
        Text(r.status.toUpperCase(),
            style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_rounded,
              size: 64, color: context.appColors.textMuted),
          const SizedBox(height: 16),
          Text("No attendance records found.",
              style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }
}
