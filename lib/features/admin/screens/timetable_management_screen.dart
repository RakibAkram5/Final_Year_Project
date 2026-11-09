import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/models/timetable_slot.dart';
import '../../../data/remote/auth_service.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../logic/timetable_provider.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/responsive/responsive_row.dart';
import '../../../widgets/web/web_shell.dart';

class TimetableManagementScreen extends StatefulWidget {
  const TimetableManagementScreen({super.key});

  @override
  State<TimetableManagementScreen> createState() =>
      _TimetableManagementScreenState();
}

class _TimetableManagementScreenState extends State<TimetableManagementScreen> {
  int? _dayFilter; // null = all days
  String? _classFilter; // classId, null = all classes
  String? _teacherFilter; // teacherId, null = all teachers
  List<AppUser> _teachers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthProvider>().currentUser;
      final academyId = user?.academyId ?? '';
      if (academyId.isEmpty) return;
      context.read<ClassProvider>().listenAll(academyId);
      try {
        final teachers =
            await AuthService().getApprovedByRole(UserRole.teacher, academyId);
        if (mounted) setState(() => _teachers = teachers);
      } catch (_) {
        // Teacher dropdown just stays empty; class-based slots still work.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final academyId = user?.academyId ?? '';
    final classes = context.watch<ClassProvider>().classes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable Management',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: academyId.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textOnAccent,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Slot'),
              onPressed: () => _openSlotSheet(academyId, classes),
            ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(academyId, classes),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final academyId = user?.academyId ?? '';
    final classes = context.watch<ClassProvider>().classes;
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));

    return WebAppShell(
      title: 'Timetable Management',
      titleIcon: Icons.schedule_rounded,
      navSections: navSections,
      activeNavId: 'timetable',
      user: user,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Timetable Management',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              if (academyId.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _openSlotSheet(academyId, classes),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Slot'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textOnAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _body(academyId, classes)),
        ],
      ),
    );
  }

  Widget _body(String academyId, List<ClassEntity> classes) {
    return academyId.isEmpty
        ? const Center(child: Text('Invalid session'))
        : Column(
            children: [
              _buildFilterBar(classes),
              Expanded(
                child: StreamBuilder<List<TimetableSlot>>(
                  stream: context.read<TimetableProvider>().watchAll(academyId),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent));
                    }
                    if (snap.hasError) {
                      return Center(
                          child: Text('Error loading timetable: ${snap.error}',
                              style: const TextStyle(color: AppColors.danger)));
                    }
                    var slots = snap.data ?? const [];
                    if (_dayFilter != null) {
                      slots = slots
                          .where((s) => s.dayOfWeek == _dayFilter)
                          .toList();
                    }
                    if (_classFilter != null) {
                      slots = slots
                          .where((s) => s.classId == _classFilter)
                          .toList();
                    }
                    if (_teacherFilter != null) {
                      slots = slots
                          .where((s) => s.teacherId == _teacherFilter)
                          .toList();
                    }
                    if (slots.isEmpty) {
                      return _emptyState();
                    }
                    return _buildGroupedList(slots, classes, academyId);
                  },
                ),
              ),
            ],
          );
  }

  Widget _buildFilterBar(List<ClassEntity> classes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _dayChip('All Days', null),
                for (var d = 1; d <= 7; d++)
                  _dayChip(
                      TimetableSlot.weekdayNames[d - 1].substring(0, 3), d),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ResponsiveRow(
            children: [
              _filterDropdown<String?>(
                hint: 'All Classes',
                value: _classFilter,
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: DropdownLabel('All Classes')),
                  ...classes.map((c) => DropdownMenuItem<String?>(
                      value: c.id, child: DropdownLabel(c.displayLabel))),
                ],
                onChanged: (v) => setState(() => _classFilter = v),
              ),
              _filterDropdown<String?>(
                hint: 'All Teachers',
                value: _teacherFilter,
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: DropdownLabel('All Teachers')),
                  ..._teachers.map((t) => DropdownMenuItem<String?>(
                      value: t.uid, child: DropdownLabel(t.fullName))),
                ],
                onChanged: (v) => setState(() => _teacherFilter = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayChip(String label, int? day) {
    final selected = _dayFilter == day;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _dayFilter = day),
        selectedColor: AppColors.accent.withValues(alpha: 0.2),
        labelStyle: TextStyle(
            color: selected
                ? context.appColors.accentText
                : context.appColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12),
      ),
    );
  }

  Widget _filterDropdown<T>({
    required String hint,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.appColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: context.appColors.surfaceAlt,
          style: TextStyle(color: context.appColors.textPrimary, fontSize: 13),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_month_rounded,
              size: 56,
              color: context.appColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No timetable slots yet',
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Tap "Add Slot" to start building the schedule.',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildGroupedList(
      List<TimetableSlot> slots, List<ClassEntity> classes, String academyId) {
    final byDay = <int, List<TimetableSlot>>{};
    for (final s in slots) {
      byDay.putIfAbsent(s.dayOfWeek, () => []).add(s);
    }
    final days = byDay.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final daySlots = byDay[day]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(TimetableSlot.weekdayNames[day - 1].toUpperCase(),
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              ...daySlots.map((s) => _slotCard(s, classes, academyId)),
            ],
          ),
        );
      },
    );
  }

  Widget _slotCard(
      TimetableSlot slot, List<ClassEntity> classes, String academyId) {
    return InkWell(
      onTap: () => _openSlotSheet(academyId, classes, existing: slot),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  (slot.isBreak ? AppColors.warning : context.appColors.border)
                      .withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: slot.isBreak ? AppColors.warning : AppColors.accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.displayLabel,
                      style: TextStyle(
                          color: context.appColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(slot.timeRangeLabel,
                      style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12)),
                  if (!slot.isBreak && slot.teacherName.isNotEmpty)
                    Text(
                        '${slot.teacherName}'
                        '${slot.room.isNotEmpty ? ' • ${slot.room}' : ''}',
                        style: TextStyle(
                            color: context.appColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.appColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _openSlotSheet(String academyId, List<ClassEntity> classes,
      {TimetableSlot? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddSlotSheet(
        academyId: academyId,
        classes: classes,
        existing: existing,
      ),
    );
  }
}

class _AddSlotSheet extends StatefulWidget {
  final String academyId;
  final List<ClassEntity> classes;
  final TimetableSlot? existing;
  const _AddSlotSheet(
      {required this.academyId, required this.classes, this.existing});

  @override
  State<_AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<_AddSlotSheet> {
  final _roomCtrl = TextEditingController();
  final _semesterCtrl = TextEditingController();

  bool _isBreak = false;
  ClassEntity? _selectedClass;
  // Multiple days on create (one slot gets written per day); a single day
  // when editing an existing slot, since that edits one specific entry.
  Set<int> _selectedDays = {DateTime.monday};
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  DateTime _effectiveFrom = DateTime.now();
  DateTime? _effectiveTo;
  bool _saving = false;
  Set<String> _busyTeacherIds = {};

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _isBreak = existing.isBreak;
      final classMatches =
          widget.classes.where((c) => c.id == existing.classId).toList();
      _selectedClass = classMatches.isEmpty ? null : classMatches.first;
      _selectedDays = {existing.dayOfWeek};
      _startTime = TimeOfDay(
          hour: existing.startMinutes ~/ 60,
          minute: existing.startMinutes % 60);
      _endTime = TimeOfDay(
          hour: existing.endMinutes ~/ 60, minute: existing.endMinutes % 60);
      _roomCtrl.text = existing.room;
      _semesterCtrl.text = existing.semester;
      _effectiveFrom = existing.effectiveFrom;
      _effectiveTo = existing.effectiveTo;
    }
    _refreshBusyTeachers();
  }

  /// Recomputes which teachers are already booked for the currently chosen
  /// day(s)/time/date-range (union across every selected day), so the CLASS
  /// dropdown can hide classes taught by an unavailable teacher instead of
  /// only rejecting the pick on save.
  Future<void> _refreshBusyTeachers() async {
    final startMinutes = _timeToMinutes(_startTime);
    final endMinutes = _timeToMinutes(_endTime);
    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes ||
        _selectedDays.isEmpty) {
      if (mounted) setState(() => _busyTeacherIds = {});
      return;
    }
    try {
      final provider = context.read<TimetableProvider>();
      final results =
          await Future.wait(_selectedDays.map((day) => provider.busyTeacherIds(
                academyId: widget.academyId,
                dayOfWeek: day,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                effectiveFrom: _effectiveFrom,
                effectiveTo: _effectiveTo,
                excludeSlotId: widget.existing?.id,
              )));
      final busy = results.expand((s) => s).toSet();
      if (mounted) setState(() => _busyTeacherIds = busy);
    } catch (_) {
      // Non-fatal: dropdown just stays unfiltered, findConflict() on save
      // still catches any real double-booking.
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (widget.existing != null) {
        // Editing one specific slot: picking a day always replaces it.
        _selectedDays = {day};
      } else if (_selectedDays.contains(day)) {
        if (_selectedDays.length > 1) _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
    _refreshBusyTeachers();
  }

  @override
  void dispose() {
    _roomCtrl.dispose();
    _semesterCtrl.dispose();
    super.dispose();
  }

  int? _timeToMinutes(TimeOfDay? t) =>
      t == null ? null : t.hour * 60 + t.minute;

  Future<void> _pickTime({required bool isStart}) async {
    final initial = (isStart ? _startTime : _endTime) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
    _refreshBusyTeachers();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _effectiveFrom : (_effectiveTo ?? _effectiveFrom);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _effectiveFrom = picked;
      } else {
        _effectiveTo = picked;
      }
    });
    _refreshBusyTeachers();
  }

  Future<void> _save() async {
    if (!_isBreak && _selectedClass == null) {
      _showError('Please select a class, or mark this slot as a break.');
      return;
    }
    if (_selectedDays.isEmpty) {
      _showError('Please select at least one day.');
      return;
    }
    final startMinutes = _timeToMinutes(_startTime);
    final endMinutes = _timeToMinutes(_endTime);
    if (startMinutes == null || endMinutes == null) {
      _showError('Please set both a start and end time.');
      return;
    }
    if (endMinutes <= startMinutes) {
      _showError('End time must be after the start time.');
      return;
    }
    if (_effectiveTo != null && _effectiveTo!.isBefore(_effectiveFrom)) {
      _showError('Effective-to date must be after the effective-from date.');
      return;
    }

    setState(() => _saving = true);
    try {
      final provider = context.read<TimetableProvider>();
      final cls = _isBreak ? null : _selectedClass;
      final days = _selectedDays.toList()..sort();

      // Check every selected day for conflicts before writing anything, so
      // a multi-day save either fully succeeds or fully fails.
      for (final day in days) {
        final conflict = await provider.findConflict(
          academyId: widget.academyId,
          dayOfWeek: day,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          teacherId: cls?.primaryTeacherId ?? '',
          room: _roomCtrl.text,
          className: cls?.className ?? '',
          section: cls?.section ?? '',
          effectiveFrom: _effectiveFrom,
          effectiveTo: _effectiveTo,
          excludeSlotId: widget.existing?.id,
        );
        if (conflict != null) {
          _showError('${TimetableSlot.weekdayNames[day - 1]}: $conflict');
          setState(() => _saving = false);
          return;
        }
      }

      if (widget.existing != null) {
        final slot = TimetableSlot(
          id: widget.existing!.id,
          academyId: widget.academyId,
          isBreak: _isBreak,
          classId: cls?.id ?? '',
          className: cls?.className ?? '',
          section: cls?.section ?? '',
          subject: cls?.subject ?? '',
          teacherId: cls?.primaryTeacherId ?? '',
          teacherName: cls?.primaryTeacherName ?? '',
          dayOfWeek: days.first,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          room: _roomCtrl.text.trim(),
          semester: _semesterCtrl.text.trim(),
          effectiveFrom: _effectiveFrom,
          effectiveTo: _effectiveTo,
        );
        await provider.updateSlot(slot);
      } else {
        for (final day in days) {
          await provider.createSlot(TimetableSlot(
            id: const Uuid().v4(),
            academyId: widget.academyId,
            isBreak: _isBreak,
            classId: cls?.id ?? '',
            className: cls?.className ?? '',
            section: cls?.section ?? '',
            subject: cls?.subject ?? '',
            teacherId: cls?.primaryTeacherId ?? '',
            teacherName: cls?.primaryTeacherName ?? '',
            dayOfWeek: day,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            room: _roomCtrl.text.trim(),
            semester: _semesterCtrl.text.trim(),
            effectiveFrom: _effectiveFrom,
            effectiveTo: _effectiveTo,
          ));
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(widget.existing != null
                ? 'Slot updated!'
                : '${days.length} slot${days.length == 1 ? '' : 's'} added!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('Failed to save slot: $e');
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: const Text('Delete this slot?'),
        content: const Text('This will remove it from every portal.'),
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
    if (!mounted) return;
    try {
      await context.read<TimetableProvider>().deleteSlot(id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Slot deleted'), backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to delete slot: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing != null ? 'Edit Slot' : 'Add Slot',
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('This is a break (no class)',
                  style: TextStyle(
                      color: context.appColors.textPrimary, fontSize: 14)),
              value: _isBreak,
              activeThumbColor: AppColors.accent,
              onChanged: (v) => setState(() {
                _isBreak = v;
                if (v) _selectedClass = null;
              }),
            ),
            if (!_isBreak) ...[
              Text('CLASS',
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                // Only offer classes whose primary teacher is free at the
                // chosen day/time — "assign only available teachers" as a
                // proactive filter instead of a reject-after-pick error.
                // The currently-selected class always stays visible so
                // editing an existing (now-conflicting-with-itself) slot
                // doesn't silently clear the selection.
                final available = widget.classes
                    .where((c) =>
                        c.primaryTeacherId.isEmpty ||
                        !_busyTeacherIds.contains(c.primaryTeacherId) ||
                        c.id == _selectedClass?.id)
                    .toList();
                final hiddenCount = widget.classes.length - available.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                          color: context.appColors.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.appColors.border)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<ClassEntity>(
                          value: _selectedClass,
                          isExpanded: true,
                          dropdownColor: context.appColors.surfaceAlt,
                          hint: const Text('Select a class'),
                          items: available
                              .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: DropdownLabel(c.displayLabel)))
                              .toList(),
                          onChanged: (c) => setState(() => _selectedClass = c),
                        ),
                      ),
                    ),
                    if (hiddenCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                          '$hiddenCount class${hiddenCount == 1 ? '' : 'es'} hidden — teacher already booked at this time.',
                          style: const TextStyle(
                              color: AppColors.warning, fontSize: 11)),
                    ],
                  ],
                );
              }),
              const SizedBox(height: 16),
            ],
            Text(
                widget.existing != null
                    ? 'DAY OF WEEK'
                    : 'DAY(S) OF WEEK — select one or more',
                style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label:
                        Text(TimetableSlot.weekdayNames[d - 1].substring(0, 3)),
                    selected: _selectedDays.contains(d),
                    onSelected: (_) => _toggleDay(d),
                    selectedColor: AppColors.accent.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.accent,
                    labelStyle: TextStyle(
                        color: _selectedDays.contains(d)
                            ? context.appColors.accentText
                            : context.appColors.textSecondary,
                        fontWeight: _selectedDays.contains(d)
                            ? FontWeight.bold
                            : FontWeight.normal),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _pickerField(
                        'START TIME',
                        _startTime?.format(context) ?? 'Select time',
                        () => _pickTime(isStart: true))),
                const SizedBox(width: 12),
                Expanded(
                    child: _pickerField(
                        'END TIME',
                        _endTime?.format(context) ?? 'Select time',
                        () => _pickTime(isStart: false))),
              ],
            ),
            const SizedBox(height: 16),
            LabeledField(
                label: 'Room', hint: 'e.g. Room 101', controller: _roomCtrl),
            LabeledField(
                label: 'Semester / Session',
                hint: 'e.g. Fall 2026',
                controller: _semesterCtrl),
            Row(
              children: [
                Expanded(
                    child: _pickerField(
                        'EFFECTIVE FROM',
                        _formatDate(_effectiveFrom),
                        () => _pickDate(isFrom: true))),
                const SizedBox(width: 12),
                Expanded(
                    child: _pickerField(
                        'EFFECTIVE TO (OPTIONAL)',
                        _effectiveTo != null
                            ? _formatDate(_effectiveTo!)
                            : 'Ongoing',
                        () => _pickDate(isFrom: false))),
              ],
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: widget.existing != null ? 'SAVE CHANGES' : 'ADD SLOT',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                label: const Text('Delete Slot',
                    style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: AppColors.danger),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _pickerField(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: context.appColors.inputFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                    child: Text(value,
                        style:
                            TextStyle(color: context.appColors.textPrimary))),
                Icon(Icons.arrow_drop_down,
                    color: context.appColors.accentText),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
