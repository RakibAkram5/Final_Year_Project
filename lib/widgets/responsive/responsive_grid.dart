import 'package:flutter/material.dart';

/// A non-scrolling grid whose rows grow to fit their content.
///
/// Replaces `GridView.count(childAspectRatio: ...)` for dashboard tiles: a
/// fixed aspect ratio cuts off text on small phones (320 px) and with large
/// accessibility font sizes. Here the column count follows the available
/// width and every row is as tall as its tallest tile (never shorter than
/// [minTileHeight]).
class ResponsiveTileGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double minTileHeight;

  /// Target minimum tile width used to derive the column count.
  final double minTileWidth;
  final int maxColumns;

  const ResponsiveTileGrid({
    super.key,
    required this.children,
    this.spacing = 12,
    this.minTileHeight = 104,
    this.minTileWidth = 140,
    this.maxColumns = 4,
  });

  static int columnsFor(double width,
      {double minTileWidth = 140, double spacing = 12, int maxColumns = 4}) {
    final cols = ((width + spacing) / (minTileWidth + spacing)).floor();
    return cols.clamp(2, maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = columnsFor(constraints.maxWidth,
          minTileWidth: minTileWidth, spacing: spacing, maxColumns: maxColumns);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final cells = <Widget>[];
        for (var c = 0; c < cols; c++) {
          if (c > 0) cells.add(SizedBox(width: spacing));
          final index = i + c;
          cells.add(Expanded(
            child: index < children.length
                ? ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minTileHeight),
                    child: children[index],
                  )
                : const SizedBox.shrink(),
          ));
        }
        if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      );
    });
  }
}
