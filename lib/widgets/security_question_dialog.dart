import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/theme_extensions.dart';
import '../data/models/app_user.dart';
import '../data/remote/auth_service.dart';
import 'app_widgets.dart';

/// Lets the signed-in [user] set/update the security question used to
/// self-verify identity in the "forgot password" flow. Shared across every
/// dashboard's Security Settings sheet so accounts created by an admin
/// (which skip the signup form) can still set one up later.
void showSecurityQuestionDialog(BuildContext context, AppUser? user) {
  if (user == null) return;
  final answerCtrl = TextEditingController();
  String selectedQuestion = SecurityQuestions.all.first;
  bool saving = false;
  String? error;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: const Text("Recovery Question"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  "Used to verify it's really you before we re-send a "
                  "password reset link.",
                  style: TextStyle(
                      fontSize: 13, color: context.appColors.textSecondary)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.appColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedQuestion,
                    isExpanded: true,
                    dropdownColor: context.appColors.surfaceAlt,
                    items: SecurityQuestions.all
                        .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                        .toList(),
                    onChanged: (q) =>
                        setDialogState(() => selectedQuestion = q!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: "Your Answer",
                hint: "Keep it memorable",
                controller: answerCtrl,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    if (answerCtrl.text.trim().isEmpty) {
                      setDialogState(() => error = "Answer is required.");
                      return;
                    }
                    setDialogState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await AuthService().saveSecurityQuestion(
                        uid: user.uid,
                        email: user.email,
                        question: selectedQuestion,
                        answer: answerCtrl.text,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("Recovery question saved!")),
                        );
                      }
                    } catch (e) {
                      setDialogState(() {
                        saving = false;
                        error = "Could not save. Check your connection.";
                      });
                    }
                  },
            child: Text(saving ? "SAVING..." : "SAVE",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.appColors.accentText)),
          ),
        ],
      ),
    ),
  );
}
