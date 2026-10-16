import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/ui/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import 'harness.dart';

/// Wednesday 7 Oct was never seen; two stay-clear habits and one tick habit.
Future<HabitRepository> _pumpUnseenWednesday(WidgetTester tester) async {
  final db = (await tester.runAsync(
    () => openAppDatabase(databaseFactoryFfiNoIsolate, inMemoryDatabasePath),
  ))!;
  addTearDown(() => tester.runAsync(db.close));
  await tester.runAsync(() async {
    final repo = HabitRepository(db);
    await repo.addHabit(stayClear('sugar'));
    await repo.addHabit(stayClear('smoke'));
    await repo.addHabit(habit('run'));
    for (final d in [mon, tue, thu, fri, sat, sun]) {
      await repo.markSeen(d);
    }
  });
  await pumpScreen(
    tester,
    const Scaffold(body: TodayScreen()),
    overrides: [
      databaseProvider.overrideWithValue(db),
      ...(await baseOverrides()).skip(1),
    ],
    size: const Size(360, 1600),
  );
  await tester.runAsync(() async {
    await tester.tap(find.bySemanticsLabel(RegExp('^7 October')));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
  expect(find.text('Editing Wed 7 Oct'), findsOneWidget);
  expect(find.text('Not checked'), findsNWidgets(2));
  return HabitRepository(db);
}

/// What is stored for Wednesday, by habit id.
Future<Map<String, EntryState>> _wednesday(
  WidgetTester tester,
  HabitRepository repo,
) async {
  final snap = (await tester.runAsync(repo.snapshot))!;
  return {
    for (final e in snap.entries)
      if (e.day == wed) e.habitId: e.state,
  };
}

Future<void> _tapAndWait(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFont);

  testWidgets(
    '"I stayed clear" answers for its own habit only, and the section header names the buttons shown',
    (tester) async {
      final repo = await _pumpUnseenWednesday(tester);
      expect(find.text('tap Slipped or I stayed clear'), findsOneWidget);
      expect(find.text('tap Slipped if it happened'), findsNothing);

      await _tapAndWait(
        tester,
        find.bySemanticsLabel('I stayed clear: Habit sugar'),
      );
      expect(find.text('Not checked'), findsOneWidget);
      expect(await _wednesday(tester, repo), {'sugar': EntryState.done});
      expect(
        find.bySemanticsLabel('I stayed clear: Habit smoke'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Log a slip: Habit sugar'), findsOneWidget);
      expect(find.text('tap Slipped or I stayed clear'), findsOneWidget);

      await _tapAndWait(
        tester,
        find.bySemanticsLabel('I stayed clear: Habit smoke'),
      );
      expect(find.text('Not checked'), findsNothing);
      expect(find.text('tap Slipped if it happened'), findsOneWidget);
    },
  );

  testWidgets(
    'a row not checked offers Slipped too, and a slip there is logged '
    'for that habit and day',
    (tester) async {
      final repo = await _pumpUnseenWednesday(tester);
      for (final name in ['Habit sugar', 'Habit smoke']) {
        expect(find.bySemanticsLabel('I stayed clear: $name'), findsOneWidget);
        expect(find.bySemanticsLabel('Log a slip: $name'), findsOneWidget);
      }

      await _tapAndWait(
        tester,
        find.bySemanticsLabel('Log a slip: Habit sugar'),
      );
      expect(await _wednesday(tester, repo), {'sugar': EntryState.slipped});
      expect(
        find.bySemanticsLabel('Undo the slip: Habit sugar'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('I stayed clear: Habit sugar'),
        findsNothing,
      );
      expect(find.text('Not checked'), findsOneWidget);
    },
  );

  testWidgets('ticking another habit on that day does not answer for the '
      'stay-clear habits', (tester) async {
    await _pumpUnseenWednesday(tester);
    await _tapAndWait(tester, find.bySemanticsLabel('Mark done: Habit run'));
    expect(find.text('Not checked'), findsNWidgets(2));
  });
}
