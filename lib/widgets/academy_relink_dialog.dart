import 'package:flutter/material.dart';
import '../core/theme/theme_extensions.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../logic/auth_provider.dart';

/// Lets a signed-in teacher/student/parent correct their own `academy_id`
/// if their account ended up linked to the wrong school (e.g. a stale or
/// mistyped academy code at signup) — the visible symptom being that their
/// announcements, classes, or other academy-scoped data don't show up for
/// (or come from) the rest of their actual school.
Future<void> showAcademyRelinkDialog(BuildContext context) {
  final codeCtrl = TextEditingController();
  bool submitting = false;
  String? error;

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ??
            Theme.of(ctx).colorScheme.surface,
        title: const Text("Fix Academy Link"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "If your announcements, classes, or other data aren't showing "
              "up correctly, your account may be linked to the wrong "
              "academy. Enter the correct Academy Code (given by your "
              "school admin) to relink it.",
              style: TextStyle(
                  color: context.appColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: "TP-XXXXX"),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style:
                        const TextStyle(color: AppColors.danger, fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: submitting
                ? null
                : () async {
                    final code = codeCtrl.text.trim();
                    if (code.isEmpty) {
                      setDialogState(() => error = "Academy Code is required.");
                      return;
                    }
                    setDialogState(() {
                      submitting = true;
                      error = null;
                    });
                    try {
                      await ctx.read<AuthProvider>().relinkAcademy(code);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text("Academy link updated successfully!"),
                            backgroundColor: AppColors.success));
                      }
                    } catch (e) {
                      setDialogState(() {
                        submitting = false;
                        error = e.toString();
                      });
                    }
                  },
            child: Text(submitting ? "LINKING..." : "LINK",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.appColors.accentText)),
          ),
        ],
      ),
    ),
  );
}
