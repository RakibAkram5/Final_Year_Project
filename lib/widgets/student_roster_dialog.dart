import 'package:flutter/material.dart';
import '../core/theme/theme_extensions.dart';

/// Read-only roster listing for a class/section — shows each enrolled
/// student's name (and roll number, once known) instead of just a count.
Future<void> showStudentRosterDialog(
  BuildContext context, {
  required String title,
  required Map<String, String> studentNames,
  Map<String, String> rollNumbers = const {},
}) {
  final entries = studentNames.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: context.appColors.surface,
      title:
          Text(title, style: TextStyle(color: context.appColors.textPrimary)),
      content: SizedBox(
        width: double.maxFinite,
        child: entries.isEmpty
            ? Text('No students enrolled yet.',
                style: TextStyle(color: context.appColors.textSecondary))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: entries
                    .map((e) => ListTile(
                          dense: true,
                          leading: Icon(Icons.person,
                              color: context.appColors.accentText),
                          title: Text(e.value,
                              style: TextStyle(
                                  color: context.appColors.textPrimary)),
                          trailing: rollNumbers[e.key] != null &&
                                  rollNumbers[e.key]!.isNotEmpty
                              ? Text('Roll: ${rollNumbers[e.key]}',
                                  style: TextStyle(
                                      color: context.appColors.textMuted,
                                      fontSize: 12))
                              : null,
                        ))
                    .toList(),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
      ],
    ),
  );
}
