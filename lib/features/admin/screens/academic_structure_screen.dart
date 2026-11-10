import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/academic_structure.dart';
import '../../../logic/academic_structure_provider.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

/// Admin-configurable academic structure (levels like "Matric"/
/// "Intermediate", each with its own groups/streams) — replaces the old
/// fixed `AppClasses.all` list everywhere it was used.
class AcademicStructureScreen extends StatefulWidget {
  const AcademicStructureScreen({super.key});

  @override
  State<AcademicStructureScreen> createState() =>
      _AcademicStructureScreenState();
}

class _AcademicStructureScreenState extends State<AcademicStructureScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) {
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
        title: const Text('Academic Structure',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textOnAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Level'),
        onPressed: _addLevel,
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
      title: 'Academic Structure',
      titleIcon: Icons.school_rounded,
      navSections: navSections,
      activeNavId: 'academic_structure',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Academic Structure',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                onPressed: _addLevel,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Level'),
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
    return Consumer<AcademicStructureProvider>(
      builder: (context, provider, _) {
        if (provider.loading) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        final levels = provider.structure.levels;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: levels.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _levelCard(context, provider, levels[i], i),
        );
      },
    );
  }

  Widget _levelCard(BuildContext context, AcademicStructureProvider provider,
      AcademicLevel level, int index) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(level.name,
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              subtitle: Text(
                  '${level.groups.length} group${level.groups.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: context.appColors.textSecondary, fontSize: 12)),
              trailing: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: context.appColors.textMuted),
                onSelected: (v) {
                  if (v == 'add_group') _addGroup(provider, index, level);
                  if (v == 'delete_level') _deleteLevel(provider, index);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add_group', child: Text('Add Group')),
                  PopupMenuItem(
                      value: 'delete_level', child: Text('Delete Level')),
                ],
              ),
              children: [
                if (level.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text('No groups yet. Use the menu to add one.',
                        style: TextStyle(
                            color: context.appColors.textMuted, fontSize: 12)),
                  ),
                for (final group in level.groups)
                  ListTile(
                    leading: Icon(Icons.class_rounded,
                        color: context.appColors.accentText),
                    title: Text(group,
                        style: TextStyle(color: context.appColors.textPrimary)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.danger),
                      onPressed: () =>
                          _deleteGroup(provider, index, level, group),
                    ),
                  ),
              ],
            ),
          )),
    );
  }

  Future<void> _addLevel() async {
    final provider = context.read<AcademicStructureProvider>();
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New academic level'),
        content: LabeledField(
            label: 'Level name', hint: 'e.g. Matric', controller: ctrl),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final levels = [
      ...provider.structure.levels,
      AcademicLevel(name: name, groups: const [])
    ];
    await provider.updateStructure(provider.structure.copyWith(levels: levels));
  }

  Future<void> _addGroup(AcademicStructureProvider provider, int index,
      AcademicLevel level) async {
    final ctrl = TextEditingController();
    final group = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New group in ${level.name}'),
        content: LabeledField(
            label: 'Group name', hint: 'e.g. Science', controller: ctrl),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (group == null || group.isEmpty) return;
    final levels = [...provider.structure.levels];
    levels[index] = level.copyWith(groups: [...level.groups, group]);
    await provider.updateStructure(provider.structure.copyWith(levels: levels));
  }

  Future<void> _deleteGroup(AcademicStructureProvider provider, int index,
      AcademicLevel level, String group) async {
    final levels = [...provider.structure.levels];
    levels[index] =
        level.copyWith(groups: level.groups.where((g) => g != group).toList());
    await provider.updateStructure(provider.structure.copyWith(levels: levels));
  }

  Future<void> _deleteLevel(
      AcademicStructureProvider provider, int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this level?'),
        content: const Text(
            'All groups under it will be removed from the picker too.'),
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
    final levels = [...provider.structure.levels]..removeAt(index);
    await provider.updateStructure(provider.structure.copyWith(levels: levels));
  }
}
