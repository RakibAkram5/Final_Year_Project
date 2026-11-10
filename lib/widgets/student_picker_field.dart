import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/theme_extensions.dart';
import '../data/models/app_user.dart';
import '../data/remote/auth_service.dart';

/// Debounced student-name/email search + multi-select chips, used by the
/// admin "Add/Edit Parent" sheets to link a parent to one or more students
/// (reuses [AuthService.searchStudentsByName] — the same lookup already
/// used by the Parent Portal's own "link a child" flow).
class StudentPickerField extends StatefulWidget {
  final String academyId;
  final List<AppUser> initiallySelected;
  final ValueChanged<List<AppUser>> onChanged;

  const StudentPickerField({
    super.key,
    required this.academyId,
    this.initiallySelected = const [],
    required this.onChanged,
  });

  @override
  State<StudentPickerField> createState() => _StudentPickerFieldState();
}

class _StudentPickerFieldState extends State<StudentPickerField> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<AppUser> _results = [];
  bool _searching = false;
  late List<AppUser> _selected;

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initiallySelected];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      final results =
          await AuthService().searchStudentsByName(widget.academyId, q);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = results
            .where((s) => !_selected.any((sel) => sel.uid == s.uid))
            .toList();
      });
    });
  }

  void _select(AppUser student) {
    setState(() {
      _selected.add(student);
      _results.removeWhere((s) => s.uid == student.uid);
      _searchCtrl.clear();
    });
    widget.onChanged(_selected);
  }

  void _remove(AppUser student) {
    setState(() => _selected.removeWhere((s) => s.uid == student.uid));
    widget.onChanged(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Linked Children',
            style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selected
                  .map((s) => Chip(
                        label: Text(s.fullName,
                            style: TextStyle(
                                color: context.appColors.textPrimary,
                                fontSize: 12)),
                        onDeleted: () => _remove(s),
                        backgroundColor:
                            AppColors.accent.withValues(alpha: 0.12),
                        deleteIconColor: AppColors.accent,
                        side: BorderSide.none,
                      ))
                  .toList(),
            ),
          ),
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          style: TextStyle(color: context.appColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search student by name or email...',
            prefixIcon: Icon(Icons.search_rounded,
                color: context.appColors.accentText, size: 20),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent)),
                  )
                : null,
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: context.appColors.inputFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appColors.border),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final s = _results[i];
                return ListTile(
                  dense: true,
                  title: Text(s.fullName,
                      style: TextStyle(color: context.appColors.textPrimary)),
                  subtitle: Text(s.email,
                      style: TextStyle(
                          color: context.appColors.textMuted, fontSize: 11)),
                  onTap: () => _select(s),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
