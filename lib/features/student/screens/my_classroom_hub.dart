import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/class_entity.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import 'teacher_details_screen.dart';

class MyClassroomHub extends StatefulWidget {
  const MyClassroomHub({super.key});

  @override
  State<MyClassroomHub> createState() => _MyClassroomHubState();
}

class _MyClassroomHubState extends State<MyClassroomHub> {
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
        title: const Text('My Classroom Hub',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildStudentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'My Classroom Hub',
      titleIcon: Icons.school_rounded,
      navSections: navSections,
      activeNavId: 'classroom_hub',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(),
    );
  }

  Widget _body() {
    final user = context.watch<AuthProvider>().currentUser;
    final classProv = context.watch<ClassProvider>();

    // Find all classes where this student is enrolled
    final enrolledClasses = classProv.classes
        .where((c) => c.studentIds.contains(user?.uid))
        .toList();

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: enrolledClasses.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: enrolledClasses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) =>
                    _teacherTile(enrolledClasses[index]),
              ),
      ),
    );
  }

  Widget _teacherTile(ClassEntity cls) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            contentPadding: const EdgeInsets.all(20),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.accent.withValues(alpha: 0.1),
              child: Text(
                  cls.primaryTeacherName.isNotEmpty
                      ? cls.primaryTeacherName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: context.appColors.accentText,
                      fontWeight: FontWeight.bold,
                      fontSize: 20)),
            ),
            title: Text(cls.primaryTeacherName,
                style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text("${cls.subject} • ${cls.className} (${cls.section})",
                    style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _smallBadge(Icons.menu_book_rounded, "Resources"),
                    _smallBadge(Icons.question_answer_rounded, "Discussions"),
                  ],
                ),
              ],
            ),
            trailing: Icon(Icons.chevron_right_rounded,
                color: context.appColors.accentText),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TeacherDetailsScreen(classEntity: cls)),
            ),
          )),
    );
  }

  Widget _smallBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.appColors.accentText),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.school_outlined,
            size: 80,
            color: context.appColors.textMuted.withValues(alpha: 0.3)),
        const SizedBox(height: 20),
        Text("No teachers assigned yet",
            style: TextStyle(
                color: context.appColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("Contact your admin to enroll in classes.",
            style: TextStyle(color: context.appColors.textSecondary)),
      ],
    );
  }
}
