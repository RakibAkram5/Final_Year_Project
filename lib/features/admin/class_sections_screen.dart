import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/app_user.dart';
import '../../data/models/class_section.dart';
import '../../data/remote/auth_service.dart';
import '../../logic/academic_structure_provider.dart';
import '../../logic/auth_provider.dart';
import '../../logic/class_section_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/student_roster_dialog.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';

/// Where enrollment actually lives: one roster per class+section.
/// Subject offerings in Class Management just point at a section here
/// instead of keeping their own copy of the student list.
class ClassSectionsScreen extends StatefulWidget {
  const ClassSectionsScreen({super.key});

  @override
  State<ClassSectionsScreen> createState() => _ClassSectionsScreenState();
}

class _ClassSectionsScreenState extends State<ClassSectionsScreen> {
  String get _academyId =>
      Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user != null) {
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
        title: const Text('Classes & Sections',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
      title: 'Classes & Sections',
      titleIcon: Icons.groups_2_rounded,
      navSections: navSections,
      activeNavId: 'class_sections',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: _body(),
    );
  }

  Widget _body() {
    return Consumer2<ClassSectionProvider, AcademicStructureProvider>(
      builder: (context, sp, structure, _) {
        if (sp.loading || structure.loading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final classNames = structure.flatClassNames;
        if (sp.error != null && sp.sections.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load class sections.\n${sp.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: classNames.length,
          itemBuilder: (_, i) =>
              _classGroup(classNames[i], sp.forClass(classNames[i])),
        );
      },
    );
  }

  Widget _classGroup(String className, List<ClassSectionEntity> sections) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: sections.isNotEmpty,
          title: Text(className,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          subtitle: Text(
              '${sections.length} section${sections.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_rounded, color: AppColors.accent),
            tooltip: 'Add Section',
            onPressed: () => _openAddSectionDialog(className),
          ),
          children: [
            if (sections.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text('No sections yet. Tap + to add one.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            for (final s in sections) _sectionTile(s),
          ],
        ),
      ),
    );
  }

  Widget _sectionTile(ClassSectionEntity s) {
    return ListTile(
      leading: const Icon(Icons.groups_rounded, color: AppColors.accent),
      title: Text('Section ${s.section.isEmpty ? '-' : s.section}',
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${s.enrollmentCount} student${s.enrollmentCount == 1 ? '' : 's'} enrolled',
          style: const TextStyle(color: AppColors.accent, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.visibility_rounded, color: AppColors.accent),
            tooltip: 'View Students',
            onPressed: () => showStudentRosterDialog(
              context,
              title: s.displayLabel,
              studentNames: s.studentNames,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.group_add_rounded, color: AppColors.accent),
            tooltip: 'Manage Enrollment',
            onPressed: () => _openEnrollmentSheet(s),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            tooltip: 'Delete Section',
            onPressed: () => _confirmDeleteSection(s),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddSectionDialog(String className) async {
    final ctrl = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text('New section in $className',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'e.g. A, B, Morning'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child:
                const Text('Create', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;

    if (context.read<ClassSectionProvider>().sectionExists(
          className: className,
          program: '',
          section: result,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Section "$result" already exists in $className.'),
          backgroundColor: AppColors.danger));
      return;
    }

    try {
      await context.read<ClassSectionProvider>().createSection(
            academyId: _academyId,
            className: className,
            section: result,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to create section: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Future<void> _confirmDeleteSection(ClassSectionEntity s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Delete section?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            'Remove ${s.displayLabel}? Its section roster is removed; '
            'subject classes, attendance and timetable history are kept.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ClassSectionProvider>().deleteSection(s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${s.displayLabel} deleted'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to delete section: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Future<void> _openEnrollmentSheet(ClassSectionEntity s) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
    );

    final auth = AuthService();
    List<AppUser> students = [];
    try {
      students = await auth.getApprovedByRole(UserRole.student, _academyId);
    } catch (_) {}

    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No approved students. Ask them to sign up and approve them.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EnrollmentSheet(section: s, allStudents: students),
    );
  }
}

class _EnrollmentSheet extends StatefulWidget {
  final ClassSectionEntity section;
  final List<AppUser> allStudents;
  const _EnrollmentSheet({required this.section, required this.allStudents});

  @override
  State<_EnrollmentSheet> createState() => _EnrollmentSheetState();
}

class _EnrollmentSheetState extends State<_EnrollmentSheet> {
  final Set<String> _selectedStudentUids = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedStudentUids.addAll(widget.section.studentIds);
  }

  Future<void> _save() async {
    final chosen = widget.allStudents
        .where((s) => _selectedStudentUids.contains(s.uid))
        .toList();

    setState(() => _saving = true);
    try {
      await context.read<ClassSectionProvider>().updateEnrollment(
            section: widget.section,
            students: chosen,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Enrollment updated for "${widget.section.displayLabel}"')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Could not update enrollment. Check your connection.')),
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
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Enroll Students: ${widget.section.displayLabel}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 4),
          const Text(
              'This roster is shared by every subject taught to this section.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('STUDENTS',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const Spacer(),
              Text('${_selectedStudentUids.length} selected',
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          _studentPickerList(),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Update Enrollment',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _studentPickerList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: widget.allStudents.length,
        itemBuilder: (_, i) {
          final s = widget.allStudents[i];
          final selected = _selectedStudentUids.contains(s.uid);
          return InkWell(
            onTap: () => setState(() {
              if (selected) {
                _selectedStudentUids.remove(s.uid);
              } else {
                _selectedStudentUids.add(s.uid);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: selected ? AppColors.accent : AppColors.textMuted,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.fullName,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600)),
                        Text(s.email,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
