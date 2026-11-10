import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taleemplus_app/core/theme/app_theme.dart';
import 'package:taleemplus_app/widgets/responsive/responsive_action_tile.dart';
import 'package:taleemplus_app/widgets/responsive/responsive_grid.dart';
import 'package:taleemplus_app/widgets/responsive/responsive_row.dart';

import 'support/fake_api.dart';

Widget _host(double width, Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  setUpAll(loadRealFonts);

  group('ResponsiveActionTile.inlineActionCount', () {
    int count(double w, int n) => ResponsiveActionTile.inlineActionCount(
        width: w, actionCount: n, leadingWidth: 44, horizontalPadding: 28);

    test('all actions inline on wide cards', () {
      expect(count(800, 4), 4);
    });
    test('keeps the title at least minTextWidth on phones', () {
      // 360 px phone card: 360 - 32 list padding = 328 px card.
      final inline = count(328, 4);
      expect(inline, lessThan(4));
      const fixed = 28 + 44 + 12 + 4;
      final used = fixed + (inline + 1) * ResponsiveActionTile.actionExtent;
      expect(328 - used, greaterThanOrEqualTo(168));
    });
    test('everything goes to the overflow menu on tiny cards', () {
      expect(count(260, 4), 0);
    });
    test('no actions means nothing inline', () {
      expect(count(500, 0), 0);
    });
  });

  testWidgets('overflowed actions are reachable and fire from the menu',
      (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(_host(
      300,
      ResponsiveActionTile(
        leading: const Icon(Icons.class_rounded),
        title: 'Intermediate Part-II Pre-Engineering - Morning Batch A',
        actions: [
          for (final name in ['View', 'Edit', 'Fees', 'Delete'])
            TileAction(
              icon: Icons.circle,
              label: name,
              destructive: name == 'Delete',
              onPressed: () => fired.add(name),
            ),
        ],
      ),
    ));
    expect(tester.takeException(), isNull);
    // Title keeps a readable width.
    final title = tester.getSize(find.textContaining('Intermediate'));
    expect(title.width, greaterThanOrEqualTo(150));

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(fired, ['Delete']);
  });

  testWidgets('wide tile shows every action inline with tooltips',
      (tester) async {
    await tester.pumpWidget(_host(
      900,
      ResponsiveActionTile(
        title: 'Class',
        actions: [
          for (final name in ['View', 'Edit', 'Fees', 'Delete'])
            TileAction(icon: Icons.circle, label: name, onPressed: () {}),
        ],
      ),
    ));
    expect(find.byTooltip('More actions'), findsNothing);
    for (final name in ['View', 'Edit', 'Fees', 'Delete']) {
      expect(find.byTooltip(name), findsOneWidget);
    }
  });

  group('ResponsiveTileGrid', () {
    test('column count follows width', () {
      expect(ResponsiveTileGrid.columnsFor(280), 2);
      expect(ResponsiveTileGrid.columnsFor(728), 4);
      expect(ResponsiveTileGrid.columnsFor(500), 3);
    });

    testWidgets('rows grow with content instead of clipping', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_host(
        280,
        SingleChildScrollView(
          child: ResponsiveTileGrid(children: [
            for (var i = 0; i < 3; i++)
              Card(
                child: Column(children: [
                  const Icon(Icons.star),
                  const Spacer(),
                  Text('Tile $i title that wraps onto several lines'),
                ]),
              ),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ResponsiveRow stacks below its breakpoint', (tester) async {
    Widget row(double w) => _host(
          w,
          const ResponsiveRow(children: [Text('A'), Text('B')]),
        );
    await tester.pumpWidget(row(300));
    expect(tester.getTopLeft(find.text('B')).dy,
        greaterThan(tester.getTopLeft(find.text('A')).dy));
    await tester.pumpWidget(row(600));
    expect(tester.getTopLeft(find.text('B')).dy,
        tester.getTopLeft(find.text('A')).dy);
  });
}
