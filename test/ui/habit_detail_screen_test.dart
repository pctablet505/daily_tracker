import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/ui/screens/habit_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFont);

  testWidgets('a write does not blank the page to a spinner', (tester) async {
    final l = Ledger(
      habits: [habit('run')],
      entries: [entry('run', sat)],
      seenDays: [sat, sun],
    );
    await pumpScreen(
      tester,
      const HabitDetailScreen(habitId: 'run'),
      overrides: [...await baseOverrides(), ledgerByRevision(l, l)],
    );
    expect(find.text('Habit run'), findsOneWidget);
    bumpRevision(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Habit run'), findsOneWidget);
  });

  testWidgets('an archived habit names its last day, not the archive day', (
    tester,
  ) async {
    // Archived on Thursday: Wednesday was its last day.
    await pumpScreen(
      tester,
      const HabitDetailScreen(habitId: 'old'),
      overrides: await baseOverrides(
        ledger: Ledger(
          habits: [habit('old', end: wed)],
          entries: const [],
        ),
      ),
      size: const Size(360, 1200),
    );
    expect(find.textContaining('Last day Wed 7 Oct'), findsOneWidget);
    expect(find.textContaining('Archived'), findsNothing);
  });

  for (final (later, shown) in [(76.2, '+0.3 kg in 30 days'), (75.901, null)]) {
    testWidgets('the trend line for a change to $later: $shown', (
      tester,
    ) async {
      final w = habit('w', logType: LogType.number).copyWith(unit: () => 'kg');
      await pumpScreen(
        tester,
        const HabitDetailScreen(habitId: 'w'),
        overrides: await baseOverrides(
          ledger: Ledger(
            habits: [w],
            entries: [
              entry('w', sat, EntryState.done, 75.9),
              entry('w', sun, EntryState.done, later),
            ],
          ),
        ),
        size: const Size(360, 1200),
      );
      // A change too small to show as a number is not shown as "+0".
      expect(
        find.textContaining('in 30 days'),
        shown == null ? findsNothing : findsOneWidget,
      );
      if (shown != null) expect(find.text(shown), findsOneWidget);
    });
  }

  testWidgets('older photos can be paged in', (tester) async {
    final pic = habit('pic', logType: LogType.photo, created: sun.addDays(-40));
    await pumpScreen(
      tester,
      const HabitDetailScreen(habitId: 'pic'),
      overrides: await baseOverrides(
        ledger: Ledger(
          habits: [pic],
          entries: [
            for (var i = 0; i < 35; i++)
              entry(
                'pic',
                sun.addDays(-i),
              ).copyWith(photoPath: () => 'p$i.jpg'),
          ],
        ),
      ),
      size: const Size(360, 4000),
    );
    final semantics = tester.ensureSemantics();
    final photos = find.bySemanticsLabel(RegExp('^Photo from'));
    expect(photos, findsNWidgets(30));
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    expect(photos, findsNWidgets(35));
    expect(find.text('Show more'), findsNothing);
    semantics.dispose();
  });
}
