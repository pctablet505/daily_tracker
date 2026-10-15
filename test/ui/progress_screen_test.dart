import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/ui/screens/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFont);

  /// Progress on the morning of October [today], for a habit done on [done].
  Future<void> pumpProgress(
    WidgetTester tester, {
    required int today,
    required List<int> done,
  }) async {
    const d1 = DayKey(2026, 10, 1);
    final ledger = Ledger(
      habits: [Habit(id: 'a', name: 'Stretch', createdDay: d1)],
      entries: [
        for (final d in done)
          Entry(
            habitId: 'a',
            day: DayKey(2026, 10, d),
            state: EntryState.done,
            loggedAt: DateTime.utc(2026, 10, d),
          ),
      ],
      seenDays: [for (var d = 1; d <= today; d++) DayKey(2026, 10, d)],
    );
    await pumpScreen(
      tester,
      const Scaffold(body: ProgressScreen()),
      overrides: await baseOverrides(
        ledger: ledger,
        now: DateTime(2026, 10, today, 8),
      ),
    );
  }

  testWidgets('a write does not blank Progress to a spinner', (tester) async {
    const d1 = DayKey(2026, 10, 1);
    final l = Ledger(
      habits: [Habit(id: 'a', name: 'Stretch', createdDay: d1)],
      entries: const [],
      seenDays: const [d1],
    );
    await pumpScreen(
      tester,
      const Scaffold(body: ProgressScreen()),
      overrides: [
        ...await baseOverrides(now: DateTime(2026, 10, 1, 8)),
        ledgerByRevision(l, l),
      ],
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    bumpRevision(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('needs attention', () {
    testWidgets(
      'leaves out a habit done every day so far, on the morning of the 3rd',
      (tester) async {
        await pumpProgress(tester, today: 3, done: [1, 2]);
        expect(find.text('NEEDS ATTENTION THIS MONTH'), findsNothing);
      },
    );

    testWidgets('names a habit missed on a past day', (tester) async {
      await pumpProgress(tester, today: 4, done: [1, 3]);
      expect(find.text('NEEDS ATTENTION THIS MONTH'), findsOneWidget);
    });
  });

  group('a calendar day and its sheet', () {
    const d2 = DayKey(2026, 10, 2);
    const d5 = DayKey(2026, 10, 5);
    // The morning of the 5th. No habit yet on the 1st; a stay-clear habit
    // from the 2nd, kept clear on the 2nd, never checked on the 3rd, slipped
    // on the 4th; a tick habit from the 5th, not done yet.
    final ledger = Ledger(
      habits: [
        Habit(id: 's', name: 'No sugar', kind: HabitKind.avoid, createdDay: d2),
        Habit(id: 'a', name: 'Stretch', createdDay: d5),
      ],
      entries: [
        Entry(
          habitId: 's',
          day: const DayKey(2026, 10, 4),
          state: EntryState.slipped,
          loggedAt: DateTime.utc(2026, 10, 4),
        ),
      ],
      seenDays: const [DayKey(2026, 10, 1), d2, d5],
    );

    for (final (day, label, sheet) in [
      (1, 'nothing planned', 'Nothing was planned.'),
      (2, 'on track', 'On track, no slips.'),
      (3, 'not checked', 'Not checked.'),
      (4, '1 slip', '1 slip logged.'),
      (5, '0 of 1 done', '0 of 1 done, no slips.'),
    ]) {
      testWidgets('October $day reads "$label" and its sheet "$sheet"', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          const Scaffold(body: ProgressScreen()),
          overrides: await baseOverrides(
            ledger: ledger,
            now: DateTime(2026, 10, 5, 8),
          ),
          size: const Size(400, 1600),
        );
        final cell = find.bySemanticsLabel(RegExp('(^|, )$day October, '));
        expect(cell, findsOneWidget);
        expect(
          tester.getSemantics(cell).label,
          endsWith('$day October, $label'),
        );
        await tester.tap(cell);
        await tester.pumpAndSettle();
        expect(find.text(sheet), findsOneWidget);
      });
    }
  });

  testWidgets('today, still open, does not pull an area bar down', (
    tester,
  ) async {
    const d1 = DayKey(2026, 10, 1);
    final ledger = Ledger(
      habits: [
        Habit(id: 'a', name: 'Stretch', createdDay: d1, area: 'Health'),
        Habit(id: 'b', name: 'Read', createdDay: d1, area: 'Mind'),
      ],
      entries: [
        for (final id in ['a', 'b'])
          for (final d in [1, 2])
            Entry(
              habitId: id,
              day: DayKey(2026, 10, d),
              state: EntryState.done,
              loggedAt: DateTime.utc(2026, 10, d),
            ),
      ],
      seenDays: [for (var d = 1; d <= 3; d++) DayKey(2026, 10, d)],
    );
    // The morning of the 3rd: both done every day so far.
    await pumpScreen(
      tester,
      const Scaffold(body: ProgressScreen()),
      overrides: await baseOverrides(
        ledger: ledger,
        now: DateTime(2026, 10, 3, 8),
      ),
      size: const Size(360, 2000),
    );
    final bars = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_AreaBar',
    );
    expect(bars, findsNWidgets(2));
    expect(
      find.descendant(of: bars, matching: find.text('100%')),
      findsNWidgets(2),
    );
  });
}
