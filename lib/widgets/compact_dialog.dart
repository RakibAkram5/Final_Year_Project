import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';

/// Width-capped, content-sized dialog for small forms and confirmations.
///
/// A bare [AlertDialog] whose content holds a text field stretches to the
/// full width allowed by its inset padding, which on tablets and desktop
/// becomes a huge mostly-empty box. This keeps dialogs at a professional
/// size ([maxWidth]), scrolls long content, and uses compact action buttons.
Future<T?> showCompactDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget> actions = const [],
  double maxWidth = 420,
  bool barrierDismissible = true,
  IconData? icon,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => CompactDialog(
        title: title,
        content: content,
        actions: actions,
        maxWidth: maxWidth,
        icon: icon),
  );
}

class CompactDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;
  final IconData? icon;

  const CompactDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.maxWidth = 420,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Dialog(
      insetPadding: EdgeInsets.fromLTRB(20, 24, 20, 24 + viewInsets.bottom),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: colors.accentText),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 14, color: colors.textSecondary),
                  child: content,
                ),
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: actions,
                ),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
