import 'package:flutter/material.dart';

/// Lays [children] out side by side (each [Expanded]) when there is at least
/// [breakpoint] width, and stacked full-width below it.
///
/// Use for filter bars and paired form fields that become unreadably narrow
/// when forced into one row on a phone.
class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.breakpoint = 480,
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= breakpoint;
      final out = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        if (i > 0) {
          out.add(wide ? SizedBox(width: spacing) : SizedBox(height: spacing));
        }
        out.add(wide ? Expanded(child: children[i]) : children[i]);
      }
      return wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: out)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: out);
    });
  }
}

/// Single-line dropdown label that ellipsizes instead of wrapping mid-word.
class DropdownLabel extends StatelessWidget {
  final String text;
  const DropdownLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );
}
