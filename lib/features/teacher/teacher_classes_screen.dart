import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/class_entity.dart';
import '../../logic/auth_provider.dart';
import '../../logic/class_provider.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';
import 'screens/classroom_management_screen.dart';
import 'attendance_marking_screen.dart';

/// Where tapping a class in [TeacherClassesScreen] should jump straight to.
/// `null` (the default "My Classes" entry point) jumps straight to marking
/// attendance for that class.
enum ClassJumpTarget { resources, queries }

/// Streams the classes assigned to the logged-in teacher (matched by email
/// against `primary_teacher_email` on the class doc in Firestore).
class TeacherClassesScreen extends StatelessWidget {
  final ClassJumpTarget? jumpTo;
  const TeacherClassesScreen({super.key, this.jumpTo});

  String get _title {
    switch (jumpTo) {
      case ClassJumpTarget.resources:
        return 'Resources';
      case ClassJumpTarget.queries:
        return 'Queries';
      case null:
        return 'My Classes';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context, user);
    }
    return _buildMobileLayout(context, user);
  }

  Widget _buildMobileLayout(BuildContext context, dynamic user) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title:
            Text(_title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(context, user),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context, dynamic user) {
    final navSections = buildTeacherNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    final activeId = switch (jumpTo) {
      ClassJumpTarget.resources => 'resources',
      ClassJumpTarget.queries => 'queries',
      null => 'attendance',
    };
    return WebAppShell(
      title: _title,
      titleIcon: Icons.class_rounded,
      navSections: navSections,
      activeNavId: activeId,
      user: user,
      onLogout: () => performWebLogout(context),
      body: _body(context, user),
    );
  }

  Widget _body(BuildContext context, dynamic user) {
    return user == null
        ? const _EmptyMessage(text: 'Please log in again.')
        : StreamBuilder<List<ClassEntity>>(
            stream: context
                .read<ClassProvider>()
                .streamForTeacher(user.uid, user.academyId ?? ''),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                );
              }
              if (snap.hasError) {
                return const _EmptyMessage(text: 'Could not load classes.');
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) return _emptyState(context);
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _classTile(context, list[i]),
              );
            },
          );
  }

  Widget _emptyState(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Icon(Icons.class_outlined,
                  size: 56, color: context.appColors.textMuted),
              const SizedBox(height: 12),
              Text('No classes assigned yet',
                  style: TextStyle(color: context.appColors.textSecondary)),
              const SizedBox(height: 4),
              Text('Ask your admin to assign you a class',
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _classTile(BuildContext context, ClassEntity c) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTapClass(context, c),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.appColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.appColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.class_rounded,
                    color: context.appColors.accentText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.displayLabel,
                        style: TextStyle(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                        '${c.enrollmentCount} students'
                        '${jumpTo == null ? ' · Tap to mark attendance' : ''}',
                        style: TextStyle(
                            color: context.appColors.textSecondary,
                            fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.appColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapClass(BuildContext context, ClassEntity c) {
    if (jumpTo == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceMarkingScreen(classEntity: c),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassroomManagementScreen(
          classEntity: c,
          initialTabIndex: jumpTo == ClassJumpTarget.resources ? 1 : 0,
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final String text;
  const _EmptyMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          Text(text, style: TextStyle(color: context.appColors.textSecondary)),
    );
  }
}
