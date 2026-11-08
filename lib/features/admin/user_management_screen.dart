import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../core/web/web_breakpoints.dart';
import '../../data/models/academy_member.dart';
import '../../data/models/class_section.dart';
import '../../data/remote/auth_service.dart';
import '../../logic/academic_structure_provider.dart';
import '../../logic/auth_provider.dart';
import '../../logic/class_section_provider.dart';
import '../../logic/member_provider.dart';
import '../../data/models/app_user.dart';
import '../../logic/class_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/student_picker_field.dart';
import '../../widgets/web/web_nav_items.dart';
import '../../widgets/web/web_shell.dart';
import '../../core/theme/theme_extensions.dart';

/// "className|program|section" key format used to store a teacher's real
/// class+section assignments in AppUser.assignedSections (previously
/// hardcoded, disconnected ['A','B','C','D'] letter chips).
Widget _teacherSectionPicker(
  BuildContext context,
  Set<String> selectedKeys,
  void Function(String key, bool selected) onToggle,
) {
  return Consumer<ClassSectionProvider>(
    builder: (context, sp, _) {
      if (sp.sections.isEmpty) {
        return const Text('No class sections created yet.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12));
      }
      return Container(
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ListView(
          shrinkWrap: true,
          children: sp.sections.map((s) {
            final key = '${s.className}|${s.program}|${s.section}';
            final selected = selectedKeys.contains(key);
            return CheckboxListTile(
              dense: true,
              value: selected,
              title: Text(s.displayLabel, style: const TextStyle(fontSize: 13)),
              onChanged: (v) => onToggle(key, v ?? false),
            );
          }).toList(),
        ),
      );
    },
  );
}

class UserManagementScreen extends StatefulWidget {
  final int initialIndex;
  const UserManagementScreen({super.key, this.initialIndex = 0});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _roles = const ['teacher', 'student', 'parent'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user != null) {
        context.read<MemberProvider>().load(user.uid);
        context.read<AcademicStructureProvider>().listenAll(user.uid);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));

    return WebAppShell(
      title: 'User Management',
      titleIcon: Icons.group_rounded,
      navSections: navSections,
      activeNavId: 'user_management',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      contentPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('User Management',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: context.appColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Manage teachers, students and parents.',
                          style: TextStyle(
                              color: context.appColors.textSecondary)),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: _tabController,
                  builder: (ctx, _) {
                    final role = _roles[_tabController.index];
                    return FilledButton.icon(
                      onPressed: () => _openAddSheet(context, role),
                      icon:
                          const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: Text('Add ${_labelFor(role)}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.textOnAccent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.accent,
                unselectedLabelColor: context.appColors.textSecondary,
                tabs: const [
                  Tab(text: 'Teachers'),
                  Tab(text: 'Students'),
                  Tab(text: 'Parents'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _roles.map((r) => _RoleListTab(role: r)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('User Management',
            style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Teachers'),
            Tab(text: 'Students'),
            Tab(text: 'Parents'),
          ],
        ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabController,
        builder: (ctx, _) {
          final role = _roles[_tabController.index];
          return FloatingActionButton.extended(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.textOnAccent,
            icon: const Icon(Icons.person_add_alt_1),
            label: Text('Add ${_labelFor(role)}'),
            onPressed: () => _openAddSheet(ctx, role),
          );
        },
      ),
      body: GradientBackground(
        child: SafeArea(
          top: false,
          child: TabBarView(
            controller: _tabController,
            children: _roles.map((r) => _RoleListTab(role: r)).toList(),
          ),
        ),
      ),
    );
  }

  void _openAddSheet(BuildContext ctx, String role) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddMemberSheet(role: role),
    );
  }

  String _labelFor(String role) {
    switch (role) {
      case 'teacher':
        return 'Teacher';
      case 'student':
        return 'Student';
      case 'parent':
        return 'Parent';
      default:
        return 'Member';
    }
  }
}

class _RoleListTab extends StatefulWidget {
  final String role;
  const _RoleListTab({required this.role});

  @override
  State<_RoleListTab> createState() => _RoleListTabState();
}

class _RoleListTabState extends State<_RoleListTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = "";

  // Student tab only: studentUid -> assigned parent's name, so the admin can
  // see at a glance who each student is linked to (AppUser.linkedChildren is
  // stored on the parent's own doc, so this is a reverse lookup built once
  // per tab load rather than one query per student tile).
  Map<String, String> _parentNameByStudentUid = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.role == 'student') {
      _loadParentNames();
    }
  }

  Future<void> _loadParentNames() async {
    final admin = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (admin == null) return;
    final parents =
        await AuthService().getApprovedByRole(UserRole.parent, admin.uid);
    if (!mounted) return;
    final map = <String, String>{};
    for (final parent in parents) {
      for (final childUid in parent.linkedChildren) {
        map[childUid] = parent.fullName;
      }
    }
    setState(() => _parentNameByStudentUid = map);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<MemberProvider>(
      builder: (context, provider, _) {
        if (provider.loading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }

        var list = provider.byRole(widget.role);
        if (_query.isNotEmpty) {
          list = list
              .where((m) =>
                  m.fullName.toLowerCase().contains(_query.toLowerCase()) ||
                  m.extra.toLowerCase().contains(_query.toLowerCase()) ||
                  m.subject.toLowerCase().contains(_query.toLowerCase()) ||
                  m.rollNumber.toLowerCase().contains(_query.toLowerCase()) ||
                  m.phone.contains(_query))
              .toList();
        }

        return Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: list.isEmpty
                  ? _emptyState(widget.role)
                  : RepaintBoundary(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) => _memberTile(ctx, list[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(color: context.appColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: "Search by name or ${_labelForSearch(widget.role)}...",
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.accent, size: 20),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          fillColor: context.appColors.surface.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  String _labelForSearch(String role) {
    switch (role) {
      case 'teacher':
        return 'designation';
      case 'student':
        return 'roll number';
      case 'parent':
        return 'child name';
      default:
        return 'details';
    }
  }

  Widget _emptyState(String role) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.group_off_rounded,
              size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No ${role}s added yet',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap "Add" to create one',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(BuildContext context, AcademyMember m) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            child: Text(
              m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                const SizedBox(height: 2),
                if (m.role == 'teacher' &&
                    (m.extra.isNotEmpty || m.subject.isNotEmpty))
                  Text(
                      [
                        if (m.extra.isNotEmpty) m.extra,
                        if (m.subject.isNotEmpty) m.subject,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.accent, fontSize: 12))
                else if (m.role == 'student' && m.rollNumber.isNotEmpty)
                  Text('Roll: ${m.rollNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.accent, fontSize: 12))
                else if (m.extra.isNotEmpty)
                  Text(m.extra,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.accent, fontSize: 12)),
                if (m.role == 'student' &&
                    _parentNameByStudentUid.containsKey(m.id))
                  Text('Parent: ${_parentNameByStudentUid[m.id]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                if (m.email.isNotEmpty)
                  Text(m.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12)),
                if (m.phone.isNotEmpty)
                  Text(m.phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.appColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          if (m.role == 'teacher')
            IconButton(
              icon:
                  const Icon(Icons.add_chart_rounded, color: AppColors.accent),
              tooltip: 'Assign Class',
              onPressed: () => _openAssignClassSheet(context, m),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.accent),
            onPressed: () => _openEditSheet(context, m),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: () => _confirmDelete(context, m),
          ),
        ],
      ),
    );
  }

  void _openAssignClassSheet(BuildContext context, AcademyMember teacher) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickAssignClassSheet(teacher: teacher),
    );
  }

  void _openEditSheet(BuildContext context, AcademyMember m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditMemberSheet(member: m),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, AcademyMember m) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Deactivate member?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            '${m.fullName} will no longer be able to sign in. Their '
            'attendance, fee and marks history is kept.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Deactivate',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && ctx.mounted) {
      final user = Provider.of<AuthProvider>(ctx, listen: false).currentUser;
      if (user != null) {
        try {
          await ctx.read<MemberProvider>().removeMember(m.id, user.uid);
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text('${m.fullName} deactivated')),
            );
          }
        } catch (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                  content: Text('Failed to remove ${m.fullName}: $e'),
                  backgroundColor: AppColors.danger),
            );
          }
        }
      }
    }
  }
}

class _QuickAssignClassSheet extends StatefulWidget {
  final AcademyMember teacher;
  const _QuickAssignClassSheet({required this.teacher});

  @override
  State<_QuickAssignClassSheet> createState() => _QuickAssignClassSheetState();
}

class _QuickAssignClassSheetState extends State<_QuickAssignClassSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sectionCtrl.dispose();
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final authProv = Provider.of<AuthProvider>(context, listen: false);
      final academyId = authProv.currentUser?.uid ?? '';

      // Convert AcademyMember to a minimal AppUser for the provider
      final teacherUser = AppUser(
        uid: widget.teacher.id,
        fullName: widget.teacher.fullName,
        email: widget.teacher.email,
        phoneNumber: widget.teacher.phone,
        role: UserRole.teacher,
      );

      await context.read<ClassProvider>().createClassWithStudents(
            className: _nameCtrl.text,
            section: _sectionCtrl.text,
            subject: _subjectCtrl.text,
            teacher: teacherUser,
            students: [], // Start with empty enrollment
            academyId: academyId,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Assigned ${_subjectCtrl.text} (${_nameCtrl.text}) to ${widget.teacher.fullName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Assign Class to ${widget.teacher.fullName}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Create a new class assignment for this teacher.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            LabeledField(
                label: 'Class Name',
                hint: 'e.g. Class 10',
                controller: _nameCtrl,
                validator: Validators.fullName),
            LabeledField(
                label: 'Section (optional)',
                hint: 'e.g. A',
                controller: _sectionCtrl),
            LabeledField(
                label: 'Subject',
                hint: 'e.g. Physics',
                controller: _subjectCtrl,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Subject is required' : null),
            const SizedBox(height: 24),
            PrimaryButton(
                label: 'ASSIGN CLASS',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _EditMemberSheet extends StatefulWidget {
  final AcademyMember member;
  const _EditMemberSheet({required this.member});

  @override
  State<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends State<_EditMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _extraCtrl;
  late final TextEditingController _qualificationCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _rollNumberCtrl;
  DateTime? _joiningDate;
  final Set<String> _selectedSectionKeys = {};
  bool _saving = false;

  // Parent: current + edited set of linked children.
  List<AppUser> _selectedChildren = [];
  List<String> _originalChildUids = [];
  bool _loadingChildren = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.member.fullName);
    _phoneCtrl = TextEditingController(text: widget.member.phone);
    _extraCtrl = TextEditingController(text: widget.member.extra);
    _qualificationCtrl = TextEditingController(text: widget.member.extra);
    _subjectCtrl = TextEditingController(text: widget.member.subject);
    _rollNumberCtrl = TextEditingController(text: widget.member.rollNumber);
    _joiningDate = widget.member.createdAt;
    if (widget.member.role == 'teacher') {
      final admin =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (admin != null) {
        context.read<ClassSectionProvider>().listenAll(admin.uid);
      }
    }
    if (widget.member.role == 'parent') {
      _loadLinkedChildren();
    }
  }

  Future<void> _loadLinkedChildren() async {
    setState(() => _loadingChildren = true);
    final auth = AuthService();
    final profile = await auth.getProfile(widget.member.id);
    final children = profile == null
        ? <AppUser>[]
        : await auth.getProfilesByIds(profile.linkedChildren);
    if (!mounted) return;
    setState(() {
      _selectedChildren = children;
      _originalChildUids = children.map((c) => c.uid).toList();
      _loadingChildren = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _extraCtrl.dispose();
    _qualificationCtrl.dispose();
    _subjectCtrl.dispose();
    _rollNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final admin = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (widget.member.role == 'student' && admin != null) {
      final bool taken;
      try {
        taken = await AuthService().isRollNumberTaken(
          admin.uid,
          _rollNumberCtrl.text,
          excludeUid: widget.member.id,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not verify roll number: $e'),
            backgroundColor: AppColors.danger));
        return;
      }
      if (taken) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Roll number "${_rollNumberCtrl.text.trim()}" is already in use.'),
              backgroundColor: AppColors.danger),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final auth = AuthService();
      await auth.updateUserProfile(
        uid: widget.member.id,
        fullName: _nameCtrl.text,
        phoneNumber: _phoneCtrl.text,
        extraInfo: widget.member.role == 'teacher'
            ? _qualificationCtrl.text
            : _extraCtrl.text,
        subject: widget.member.role == 'teacher' ? _subjectCtrl.text : null,
        rollNumber:
            widget.member.role == 'student' ? _rollNumberCtrl.text : null,
        joiningDate: _joiningDate,
        sections: widget.member.role == 'teacher'
            ? _selectedSectionKeys.toList()
            : null,
      );

      if (widget.member.role == 'parent') {
        final newUids = _selectedChildren.map((c) => c.uid).toSet();
        final oldUids = _originalChildUids.toSet();
        for (final uid in newUids.difference(oldUids)) {
          await auth.addLinkedChild(widget.member.id, uid);
        }
        for (final uid in oldUids.difference(newUids)) {
          await auth.removeLinkedChild(widget.member.id, uid);
        }
      }

      if (mounted) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final admin = auth.currentUser;
        if (admin != null) {
          await context.read<MemberProvider>().load(admin.uid);
        }
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
            '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Edit Profile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            LabeledField(
                label: 'Full Name',
                hint: 'Enter name',
                controller: _nameCtrl,
                validator: Validators.fullName),
            if (widget.member.role == 'parent')
              _loadingChildren
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2)),
                    )
                  : StudentPickerField(
                      academyId: academyId,
                      initiallySelected: _selectedChildren,
                      onChanged: (children) =>
                          setState(() => _selectedChildren = children),
                    ),
            LabeledField(
                label: 'Phone',
                hint: '+92...',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                validator: Validators.phone),
            if (widget.member.role == 'teacher') ...[
              LabeledField(
                  label: 'Qualification',
                  hint: 'e.g. M.Sc Physics',
                  controller: _qualificationCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Qualification is required'
                      : null),
              LabeledField(
                  label: 'Subject',
                  hint: 'e.g. Physics',
                  controller: _subjectCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Subject is required'
                      : null),
            ],
            if (widget.member.role == 'student')
              LabeledField(
                  label: 'Roll Number',
                  hint: 'e.g. 24',
                  controller: _rollNumberCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Roll Number is required'
                      : null),
            const SizedBox(height: 12),
            if (widget.member.role == 'teacher') ...[
              const Text('Joining Date',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _joiningDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _joiningDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 18, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Text(_joiningDate == null
                          ? 'Select Date'
                          : _joiningDate!.toString().split(' ')[0]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Assigned Classes & Sections',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              _teacherSectionPicker(context, _selectedSectionKeys, (key, sel) {
                setState(() {
                  if (sel) {
                    _selectedSectionKeys.add(key);
                  } else {
                    _selectedSectionKeys.remove(key);
                  }
                });
              }),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
                label: 'UPDATE PROFILE',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _save),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saving ? null : _resetPassword,
              icon: const Icon(Icons.lock_reset_rounded,
                  color: AppColors.textSecondary),
              label: const Text('Reset password',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

extension on _EditMemberSheetState {
  /// Lets the admin set a new password when a member is locked out and has
  /// no security question. The member is signed out on all devices.
  Future<void> _resetPassword() async {
    final ctrl = TextEditingController();
    String? error;
    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceAlt,
          title: Text('Reset password for ${widget.member.fullName}?',
              style: const TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LabeledField(
                  label: 'New Password',
                  hint: '',
                  controller: ctrl,
                  obscure: true),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                final problem = Validators.password(ctrl.text);
                if (problem != null) {
                  setDialogState(() => error = problem);
                  return;
                }
                Navigator.pop(ctx, ctrl.text);
              },
              child: const Text('RESET',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (newPassword == null || !mounted) return;
    try {
      await AuthService().adminResetPassword(widget.member.id, newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Password reset for ${widget.member.fullName}. '
              'Share it with them privately.'),
          backgroundColor: AppColors.success));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to reset password: $e'),
          backgroundColor: AppColors.danger));
    }
  }
}

class _AddMemberSheet extends StatefulWidget {
  final String role;
  const _AddMemberSheet({required this.role});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _rollNumberCtrl = TextEditingController();
  final _qualificationCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  DateTime? _joiningDate = DateTime.now();

  // Teacher: real class+section assignment.
  final Set<String> _selectedSectionKeys = {};

  // Student: class-wise enrollment target.
  String? _selectedClassName;
  ClassSectionEntity? _selectedSection;

  // Parent: students to link on creation.
  List<AppUser> _selectedChildren = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final admin = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (admin != null &&
        (widget.role == 'student' || widget.role == 'teacher')) {
      context.read<ClassSectionProvider>().listenAll(admin.uid);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _rollNumberCtrl.dispose();
    _qualificationCtrl.dispose();
    _subjectCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Duplicate check before saving
    final membersProv = context.read<MemberProvider>();
    final emailLower = _emailCtrl.text.trim().toLowerCase();

    if (membersProv.members
        .any((m) => m.email.trim().toLowerCase() == emailLower)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A user with this email already exists!'),
            backgroundColor: AppColors.danger),
      );
      return;
    }

    final admin = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (admin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Session expired. Please log in again.'),
            backgroundColor: AppColors.danger),
      );
      return;
    }

    final auth = AuthService();

    // Roll number must be unique academy-wide before we create the account
    // (avoids an orphaned auth user on collision).
    if (widget.role == 'student') {
      final bool taken;
      try {
        taken = await auth.isRollNumberTaken(admin.uid, _rollNumberCtrl.text);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not verify roll number: $e'),
            backgroundColor: AppColors.danger));
        return;
      }
      if (taken) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Roll number "${_rollNumberCtrl.text.trim()}" is already in use.'),
              backgroundColor: AppColors.danger),
        );
        return;
      }
    }

    setState(() => _saving = true);

    AppUser? newUser;
    final followUpErrors = <String>[];
    try {
      // 1. Create the active account in the admin's academy (server-scoped).
      newUser = await auth.adminCreateUser(
        fullName: _nameCtrl.text,
        email: _emailCtrl.text,
        phoneNumber: _phoneCtrl.text,
        password: _passwordCtrl.text,
        role: UserRole.values.firstWhere((r) => r.name == widget.role),
        academyId: admin.uid, // PASS ACADEMY ID
        extraInfo: widget.role == 'teacher' ? _qualificationCtrl.text : null,
        subject: widget.role == 'teacher' ? _subjectCtrl.text : null,
        joiningDate: _joiningDate,
        sections:
            widget.role == 'teacher' ? _selectedSectionKeys.toList() : null,
        rollNumber: widget.role == 'student' ? _rollNumberCtrl.text : null,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to add user: $e'),
              backgroundColor: AppColors.danger),
        );
      }
      return;
    }

    // The account now exists. Follow-up steps are reported separately so a
    // failure here is never shown as "failed to add user".
    final created = newUser;

    // 2. Student: enroll into the chosen class+section (single-student
    // enroll; avoids rewriting the roster from a stale copy).
    if (widget.role == 'student' && _selectedSection != null && mounted) {
      try {
        await context.read<ClassSectionProvider>().enrollStudent(
              section: _selectedSection!,
              studentId: created.uid,
              rollNumber: _rollNumberCtrl.text,
            );
      } catch (e) {
        followUpErrors.add('section enrollment failed ($e)');
      }
    }

    // 2b. Parent: link the selected children.
    if (widget.role == 'parent') {
      for (final child in _selectedChildren) {
        try {
          await auth.addLinkedChild(created.uid, child.uid);
        } catch (e) {
          followUpErrors.add('linking ${child.fullName} failed ($e)');
        }
      }
    }

    // 3. Refresh the member list.
    if (!mounted) return;
    try {
      await context.read<MemberProvider>().load(admin.uid);
    } catch (_) {
      // The list refresh failing does not undo the creation.
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      followUpErrors.isEmpty
          ? SnackBar(
              content: Text('${_nameCtrl.text} added with active portal'))
          : SnackBar(
              content: Text('${_nameCtrl.text} was created, but '
                  '${followUpErrors.join('; ')}. Retry from Edit.'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final academyId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
            '';

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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Create ${widget.role[0].toUpperCase()}${widget.role.substring(1)} Account',
                style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Full Name',
                hint: 'Enter full name',
                controller: _nameCtrl,
                validator: Validators.fullName,
              ),
              LabeledField(
                label: 'Email Address',
                hint: 'name@taleem.edu.pk',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
              LabeledField(
                label: 'Login Password',
                hint: 'Min 6 characters',
                controller: _passwordCtrl,
                validator: Validators.password,
              ),
              if (widget.role == 'parent')
                StudentPickerField(
                  academyId: academyId,
                  onChanged: (children) =>
                      setState(() => _selectedChildren = children),
                ),
              LabeledField(
                label: 'Phone',
                hint: '+92 300 1234567',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                validator: Validators.phone,
              ),
              if (widget.role == 'teacher') ...[
                LabeledField(
                  label: 'Qualification',
                  hint: 'e.g. M.Sc Physics',
                  controller: _qualificationCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Qualification is required'
                      : null,
                ),
                LabeledField(
                  label: 'Subject',
                  hint: 'e.g. Physics',
                  controller: _subjectCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Subject is required'
                      : null,
                ),
              ],
              if (widget.role == 'student') ...[
                LabeledField(
                  label: 'Roll Number',
                  hint: 'e.g. 24',
                  controller: _rollNumberCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Roll Number is required'
                      : null,
                ),
                const SizedBox(height: 16),
                const Text('Enroll In Class (optional)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedClassName,
                    isExpanded: true,
                    hint: const Text('Select class'),
                    items: context
                        .watch<AcademicStructureProvider>()
                        .flatClassNames
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedClassName = v;
                      _selectedSection = null;
                    }),
                  ),
                ),
                if (_selectedClassName != null) ...[
                  const SizedBox(height: 8),
                  Consumer<ClassSectionProvider>(
                    builder: (context, sp, _) {
                      final sections =
                          sp.forClass(_selectedClassName!).toList();
                      return DropdownButtonHideUnderline(
                        child: DropdownButton<ClassSectionEntity>(
                          value: _selectedSection,
                          isExpanded: true,
                          hint: const Text('Select section'),
                          items: sections
                              .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text('Section ${s.section}')))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedSection = v),
                        ),
                      );
                    },
                  ),
                ],
              ],
              if (widget.role == 'teacher') ...[
                const SizedBox(height: 16),
                const Text('Joining Date',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _joiningDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded,
                            size: 18, color: AppColors.accent),
                        const SizedBox(width: 10),
                        Text(_joiningDate == null
                            ? 'Select Date'
                            : _joiningDate!.toString().split(' ')[0]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Assigned Classes & Sections',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                _teacherSectionPicker(context, _selectedSectionKeys,
                    (key, sel) {
                  setState(() {
                    if (sel) {
                      _selectedSectionKeys.add(key);
                    } else {
                      _selectedSectionKeys.remove(key);
                    }
                  });
                }),
              ],
              const SizedBox(height: 8),
              PrimaryButton(
                label: 'Create Account',
                icon: Icons.person_add_rounded,
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
