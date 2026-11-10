import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../data/models/class_entity.dart';
import '../../data/models/class_section.dart';
import '../../data/remote/auth_service.dart';
import '../../logic/academic_structure_provider.dart';
import '../../logic/auth_provider.dart';
import '../../logic/class_provider.dart';
import '../../logic/class_section_provider.dart';
import 'class_sections_screen.dart';
import 'screens/class_fee_status_screen.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/responsive/responsive_action_tile.dart';
import '../../widgets/student_roster_dialog.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/responsive/responsive_row.dart';
import '../../widgets/web/web_shell.dart';

class ClassManagementScreen extends StatefulWidget {
  const ClassManagementScreen({super.key});

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user != null) {
        context.read<ClassProvider>().listenAll(user.uid);
        context.read<ClassSectionProvider>().listenAll(user.uid);
        context.read<AcademicStructureProvider>().listenAll(user.uid);
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Class Management',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_2_rounded),
            tooltip: 'Classes & Sections',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClassSectionsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textOnAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Class'),
        onPressed: _openAddSheet,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Class Management',
      titleIcon: Icons.class_rounded,
      navSections: navSections,
      activeNavId: 'class_management',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Class Management',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ClassSectionsScreen())),
                icon: const Icon(Icons.groups_2_rounded, size: 18),
                label: const Text('Classes & Sections'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openAddSheet,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Class'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textOnAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    return Consumer<ClassProvider>(
      builder: (context, cp, _) {
        if (cp.loading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        if (cp.classes.isEmpty) return _emptyState();
        return RepaintBoundary(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: cp.classes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _classTile(cp.classes[i]),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.class_outlined,
              size: 56, color: context.appColors.textMuted),
          const SizedBox(height: 12),
          Text('No classes yet',
              style: TextStyle(color: context.appColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Tap "New Class" to create one',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _classTile(ClassEntity c) {
    final colors = context.appColors;
    return ResponsiveActionTile(
      key: ValueKey('class-tile-${c.id}'),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.class_rounded, color: context.appColors.accentText),
      ),
      title: c.displayLabel,
      subtitles: [
        if (c.primaryTeacherName.isNotEmpty)
          Text('Teacher: ${c.primaryTeacherName}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
        Text(
            '${c.enrollmentCount} student${c.enrollmentCount == 1 ? '' : 's'} enrolled',
            style:
                TextStyle(color: context.appColors.accentText, fontSize: 12)),
      ],
      actions: [
        TileAction(
          icon: Icons.visibility_rounded,
          label: 'View students',
          onPressed: () => showStudentRosterDialog(
            context,
            title: c.displayLabel,
            studentNames: c.studentNames,
          ),
        ),
        TileAction(
          icon: Icons.edit_note_rounded,
          label: 'Edit details',
          onPressed: () => _openEditClassSheet(c),
        ),
        TileAction(
          icon: Icons.payments_rounded,
          label: 'Fee status',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ClassFeeStatusScreen(classEntity: c)),
          ),
        ),
        TileAction(
          icon: Icons.delete_outline,
          label: 'Delete class',
          destructive: true,
          onPressed: () => _confirmDelete(c),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(ClassEntity c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surfaceAlt,
        title: Text('Delete class?',
            style: TextStyle(color: context.appColors.textPrimary)),
        content: Text(
            'Remove ${c.displayLabel} and all its attendance records?',
            style: TextStyle(color: context.appColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: context.appColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await context.read<ClassProvider>().deleteClass(c.id, c.academyId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${c.displayLabel} deleted'),
              backgroundColor: AppColors.success));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to delete class: $e'),
              backgroundColor: AppColors.danger));
        }
      }
    }
  }

  void _openEditClassSheet(ClassEntity c) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
    );

    final auth = AuthService();
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
            '';
    List<AppUser> teachers = [];
    try {
      teachers = await auth.getApprovedByRole(UserRole.teacher, academyId);
    } catch (_) {}

    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditClassSheet(classEntity: c, teachers: teachers),
    );
  }

  Future<void> _openAddSheet() async {
    // Show loading, fetch approved teachers + students from Firebase
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );

    final auth = AuthService();
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
            '';
    List<AppUser> teachers = [];
    List<AppUser> students = [];
    try {
      teachers = await auth.getApprovedByRole(UserRole.teacher, academyId);
      students = await auth.getApprovedByRole(UserRole.student, academyId);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
        );
      }
      return;
    }
    if (mounted) Navigator.pop(context);

    if (!mounted) return;
    if (teachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No approved teachers. Ask them to sign up and approve them.'),
        ),
      );
      return;
    }
    final availableSections = context.read<ClassSectionProvider>().sections;
    if (availableSections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'No class sections yet. Create one first from Classes & Sections.'),
          action: SnackBarAction(
            label: 'CREATE',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClassSectionsScreen()),
            ),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddClassSheet(
        teachers: teachers,
        students: students,
        sections: availableSections,
      ),
    );
  }
}

class _EditClassSheet extends StatefulWidget {
  final ClassEntity classEntity;
  final List<AppUser> teachers;
  const _EditClassSheet({required this.classEntity, required this.teachers});

  @override
  State<_EditClassSheet> createState() => _EditClassSheetState();
}

class _EditClassSheetState extends State<_EditClassSheet> {
  late final TextEditingController _subjectCtrl;
  AppUser? _selectedTeacher;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(text: widget.classEntity.subject);
    try {
      _selectedTeacher = widget.teachers
          .firstWhere((t) => t.uid == widget.classEntity.primaryTeacherId);
    } catch (_) {
      _selectedTeacher = null;
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedTeacher == null) return;

    setState(() => _saving = true);
    try {
      await context.read<ClassProvider>().updateClass(
            classId: widget.classEntity.id,
            subject: _subjectCtrl.text,
            teacher: _selectedTeacher!,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Class details updated!')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed: $e'), backgroundColor: AppColors.danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Edit Class Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          Text('CLASS & SECTION',
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
                color: context.appColors.inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.appColors.border)),
            child: Text(
                '${widget.classEntity.className} - ${widget.classEntity.section}',
                style: TextStyle(color: context.appColors.textPrimary)),
          ),
          Text(
              'Change the section from Classes & Sections instead — '
              'this only edits the subject/teacher assigned here.',
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          LabeledField(
              label: 'Subject', hint: 'e.g. Maths', controller: _subjectCtrl),
          Text('ASSIGNED TEACHER',
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: context.appColors.inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.appColors.border)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AppUser>(
                value: _selectedTeacher,
                isExpanded: true,
                dropdownColor: context.appColors.surfaceAlt,
                hint: const Text('Select a teacher'),
                items: widget.teachers
                    .map((t) => DropdownMenuItem(
                        value: t, child: DropdownLabel(t.fullName)))
                    .toList(),
                onChanged: (t) => setState(() => _selectedTeacher = t),
              ),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
              label: 'SAVE CHANGES',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _selectedTeacher == null ? null : _save),
        ],
      ),
    );
  }
}

class _AddClassSheet extends StatefulWidget {
  final List<AppUser> teachers;
  final List<AppUser> students;
  final List<ClassSectionEntity> sections;
  const _AddClassSheet({
    required this.teachers,
    required this.students,
    required this.sections,
  });

  @override
  State<_AddClassSheet> createState() => _AddClassSheetState();
}

class _AddClassSheetState extends State<_AddClassSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();

  String? _selectedClassName;
  ClassSectionEntity? _selectedSection;
  AppUser? _selectedTeacher;
  bool _saving = false;

  List<ClassSectionEntity> get _sectionsForSelectedClass =>
      widget.sections.where((s) => s.className == _selectedClassName).toList();

  @override
  void dispose() {
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeacher == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a primary teacher')),
      );
      return;
    }
    if (_selectedSection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a class and section')),
      );
      return;
    }
    final section = _selectedSection!;
    // Roster mirrors the section's roster exactly — this is what keeps
    // enrollment a one-time action per section instead of per subject.
    final chosen = widget.students
        .where((s) => section.studentIds.contains(s.uid))
        .toList();

    setState(() => _saving = true);
    try {
      final academyId =
          Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
              '';
      await context.read<ClassProvider>().createClassWithStudents(
            className: section.className,
            section: section.section,
            subject: _subjectCtrl.text,
            teacher: _selectedTeacher!,
            students: chosen,
            academyId: academyId,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Class "${section.displayLabel}" created with ${chosen.length} student(s)')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not create class. Check your connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.appColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Create Class',
                  style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 20),
              Text('CLASS',
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.appColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedClassName,
                    isExpanded: true,
                    dropdownColor: context.appColors.surfaceAlt,
                    hint: Text('Select a class',
                        style: TextStyle(color: context.appColors.textMuted)),
                    style: TextStyle(color: context.appColors.textPrimary),
                    items: context
                        .watch<AcademicStructureProvider>()
                        .flatClassNames
                        .map((c) =>
                            DropdownMenuItem(value: c, child: DropdownLabel(c)))
                        .toList(),
                    onChanged: (c) => setState(() {
                      _selectedClassName = c;
                      _selectedSection = null;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('SECTION',
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.appColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ClassSectionEntity>(
                    value: _selectedSection,
                    isExpanded: true,
                    dropdownColor: context.appColors.surfaceAlt,
                    hint: Text(
                        _selectedClassName == null
                            ? 'Pick a class first'
                            : _sectionsForSelectedClass.isEmpty
                                ? 'No sections yet — add one in Classes & Sections'
                                : 'Select a section',
                        style: TextStyle(color: context.appColors.textMuted)),
                    style: TextStyle(color: context.appColors.textPrimary),
                    items: _sectionsForSelectedClass
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                  'Section ${s.section.isEmpty ? '-' : s.section} '
                                  '(${s.enrollmentCount} students)'),
                            ))
                        .toList(),
                    onChanged: (s) => setState(() => _selectedSection = s),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Subject (optional)',
                hint: 'e.g. Physics, Mathematics',
                controller: _subjectCtrl,
              ),
              Text('PRIMARY TEACHER',
                  style: TextStyle(
                      color: context.appColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.appColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AppUser>(
                    value: _selectedTeacher,
                    isExpanded: true,
                    dropdownColor: context.appColors.surfaceAlt,
                    hint: Text('Select a teacher',
                        style: TextStyle(color: context.appColors.textMuted)),
                    style: TextStyle(color: context.appColors.textPrimary),
                    items: widget.teachers
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: DropdownLabel(t.fullName),
                            ))
                        .toList(),
                    onChanged: (t) => setState(() => _selectedTeacher = t),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                  _selectedSection == null
                      ? 'Students are enrolled once per section, from Classes & Sections.'
                      : '${_selectedSection!.enrollmentCount} student(s) from '
                          '${_selectedSection!.displayLabel} will be enrolled automatically.',
                  style: TextStyle(
                      color: context.appColors.textMuted, fontSize: 11)),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Create Class',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
