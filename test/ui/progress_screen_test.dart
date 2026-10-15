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
}
