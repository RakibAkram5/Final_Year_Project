import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';

/// Web-styled equivalent of `LabeledField` (lib/widgets/app_widgets.dart) —
/// a separate widget rather than an edit to the shared one, so the mobile
/// field keeps its exact current look. Adds a leading icon and slightly
/// roomier spacing to match the rest of the web form language.
class WebLabeledField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final bool obscure;
  final IconData? icon;
  final Widget? suffix;
  final int maxLines;
  final TextInputAction textInputAction;

  const WebLabeledField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.icon,
    this.suffix,
    this.maxLines = 1,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    final border = context.appColors.border;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            obscureText: obscure,
            maxLines: obscure ? 1 : maxLines,
            textInputAction: textInputAction,
            style:
                TextStyle(color: context.appColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon != null
                  ? Icon(icon, size: 19, color: context.appColors.textMuted)
                  : null,
              suffixIcon: suffix,
              filled: true,
              fillColor: context.appColors.inputFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: border)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.accent, width: 1.6),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.danger),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.danger, width: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Web-styled dropdown to match [WebLabeledField] — icon slot, filled
/// background, rounded border.
class WebDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final IconData? icon;
  final String hint;

  const WebDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.icon,
    this.hint = 'Select...',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.appColors.inputFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                hint: Text(hint,
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 14)),
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: context.appColors.textMuted),
                items: items
                    .map((e) => DropdownMenuItem<T>(
                          value: e,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                Icon(icon,
                                    size: 17,
                                    color: context.appColors.accentText),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: Text(itemLabel(e),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.appColors.textPrimary,
                                        fontSize: 14)),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
