import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/class_entity.dart';
import '../../logic/attendance_provider.dart';
import '../../logic/auth_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

/// Fig. 5 sequence flow — now backed by Firestore so all devices sync.
class AttendanceMarkingScreen extends StatefulWidget {
  final ClassEntity classEntity;
  const AttendanceMarkingScreen({super.key, required this.classEntity});

  @override
  State<AttendanceMarkingScreen> createState() =>
      _AttendanceMarkingScreenState();
}

class _AttendanceMarkingScreenState extends State<AttendanceMarkingScreen> {
  DateTime _selectedDate = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Sorted list of {uid, name} pairs for rendering.
  List<MapEntry<String, String>> get _studentEntries {
    final entries = widget.classEntity.studentIds.map((uid) {
      final name = widget.classEntity.studentNames[uid] ?? uid;
      return MapEntry(uid, name);
    }).toList();
    entries
        .sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return entries;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AttendanceProvider>().reset();
      _loadForDate();
    });
  }

  Future<void> _loadForDate() async {
    final academyId = context.read<AuthProvider>().currentUser?.academyId ?? '';
    await context.read<AttendanceProvider>().loadForClassDate(
          classId: widget.classEntity.id,
          date: _selectedDate,
          allStudentIds: widget.classEntity.studentIds,
          academyId: academyId,
        );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() =>
          _selectedDate = DateTime(picked.year, picked.month, picked.day));
      await _loadForDate();
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>().currentUser;
    if (auth == null) return;

    final ok = await context.read<AttendanceProvider>().save(
          classEntity: widget.classEntity,
          date: _selectedDate,
          markedByUid: auth.uid,
        );

    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Attendance saved for ${DateFormat('d MMM yyyy').format(_selectedDate)}'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      final err = context.read<AttendanceProvider>().lastError ??
          'Something went wrong';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: AppColors.danger.withValues(alpha: 0.9),
        ),
      );
    }
  }

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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.classEntity.displayLabel,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.event_rounded,
                color: context.appColors.textSecondary),
            tooltip: 'Change date',
            onPressed: _pickDate,
          ),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildTeacherNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: widget.classEntity.displayLabel,
      titleIcon: Icons.fact_check_rounded,
      navSections: navSections,
      activeNavId: 'attendance',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.classEntity.displayLabel,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: const Text('Change date'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    return Consumer<AttendanceProvider>(
      builder: (context, ap, _) {
        if (ap.loading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        if (_studentEntries.isEmpty) return _emptyState();
        return _content(ap);
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_off_rounded,
              size: 56, color: context.appColors.textMuted),
          const SizedBox(height: 12),
          Text('No students enrolled in this class',
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Ask your admin to enroll students',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _content(AttendanceProvider ap) {
    return Column(
      children: [
        _headerBar(ap),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: _studentEntries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _studentRow(_studentEntries[i], ap),
          ),
        ),
        _bottomBar(ap),
      ],
    );
  }

  Widget _headerBar(AttendanceProvider ap) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 16, color: context.appColors.accentText),
              const SizedBox(width: 8),
              Text(DateFormat('EEEE, d MMM yyyy').format(_selectedDate),
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: _pickDate,
                child: const Text('Change'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _summaryPill('Present', ap.presentCount, AppColors.success),
              const SizedBox(width: 8),
              _summaryPill('Absent', ap.absentCount, AppColors.danger),
              const SizedBox(width: 8),
              _summaryPill('Late', ap.lateCount, AppColors.warning),
              const SizedBox(width: 8),
              _summaryPill('Leave', ap.leaveCount, AppColors.accent),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side:
                    BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Mark All Present'),
              onPressed: () => context.read<AttendanceProvider>().markAll(
                    'present',
                    _studentEntries.map((e) => e.key).toList(),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text('$label: $count',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _studentRow(MapEntry<String, String> entry, AttendanceProvider ap) {
    final id = entry.key;
    final name = entry.value;
    final status = ap.statusFor(id);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
          _statusBtn('P', 'present', AppColors.success, status, id),
          const SizedBox(width: 4),
          _statusBtn('A', 'absent', AppColors.danger, status, id),
          const SizedBox(width: 4),
          _statusBtn('L', 'late', AppColors.warning, status, id),
          const SizedBox(width: 4),
          _statusBtn('E', 'leave', AppColors.accent, status, id),
        ],
      ),
    );
  }

  Widget _statusBtn(String label, String value, Color color, String current,
      String studentId) {
    final selected = current == value;
    return GestureDetector(
      onTap: () =>
          context.read<AttendanceProvider>().setStatus(studentId, value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.4),
              width: selected ? 1.4 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w800,
                fontSize: 13)),
      ),
    );
  }

  Widget _bottomBar(AttendanceProvider ap) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color:
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
              color: context.appColors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: PrimaryButton(
        label: 'Save Attendance',
        icon: Icons.save_alt_rounded,
        loading: ap.saving,
        onPressed: ap.saving ? null : _save,
      ),
    );
  }
}
