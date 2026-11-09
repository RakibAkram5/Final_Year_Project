import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../data/models/timetable_slot.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

/// Read-only weekly timetable view shared by Teacher/Student/Parent portals.
/// Each role's screen just wires up the right [stream] scope (own assigned
/// slots for a teacher, combined subject-class slots for a student/parent)
/// plus — for the web layout — that role's sidebar so the chrome still
/// matches wherever this shared view is opened from.
class TimetableView extends StatelessWidget {
  final String title;
  final Stream<List<TimetableSlot>> stream;
  final String emptyMessage;
  final List<WebNavSection>? webNavSections;
  final String? webActiveNavId;
  final AppUser? webUser;

  const TimetableView({
    super.key,
    required this.title,
    required this.stream,
    this.emptyMessage = 'No timetable slots yet.',
    this.webNavSections,
    this.webActiveNavId,
    this.webUser,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb &&
        !WebBreakpoints.isCompact(context) &&
        webNavSections != null) {
      return WebAppShell(
        title: title,
        titleIcon: Icons.schedule_rounded,
        navSections: webNavSections!,
        activeNavId: webActiveNavId ?? 'my_timetable',
        user: webUser,
        onLogout: () => performWebLogout(context),
        body: _body(context),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _body(BuildContext context) {
    return StreamBuilder<List<TimetableSlot>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snap.hasError) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error loading timetable: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger)),
          ));
        }
        final slots = snap.data ?? const [];
        if (slots.isEmpty) return _emptyState(context);

        final byDay = <int, List<TimetableSlot>>{};
        for (final s in slots) {
          byDay.putIfAbsent(s.dayOfWeek, () => []).add(s);
        }
        final days = byDay.keys.toList()..sort();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                  ...daySlots.map((s) => _slotCard(context, s)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_month_rounded,
              size: 56,
              color: context.appColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(emptyMessage,
              style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _slotCard(BuildContext context, TimetableSlot s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (s.isBreak ? AppColors.warning : context.appColors.border)
                .withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: s.isBreak ? AppColors.warning : AppColors.accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.displayLabel,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(s.timeRangeLabel,
                    style: TextStyle(
                        color: context.appColors.textSecondary, fontSize: 12)),
                if (!s.isBreak && s.teacherName.isNotEmpty)
                  Text(
                      '${s.teacherName}${s.room.isNotEmpty ? ' • ${s.room}' : ''}',
                      style: TextStyle(
                          color: context.appColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
