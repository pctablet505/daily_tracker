import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<ProviderContainer> makeContainer({
    DateTime Function()? clock,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        if (clock != null) clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    return c;
  }

  group('today', () {
    test('is the local calendar day of the clock', () async {
      final c = await makeContainer(
        clock: () => DateTime(2026, 10, 11, 23, 59),
      );
      expect(c.read(todayProvider), sun);
    });

    test('moves on by itself just after local midnight', () {
      fakeAsync((async) {
        final start = DateTime(2026, 10, 11, 23, 59, 30);
        final clock = async.getClock(start);
        final c = ProviderContainer(
          overrides: [clockProvider.overrideWithValue(clock.now)],
        );
        addTearDown(c.dispose);
        final seen = <DayKey>[];
        c.listen(todayProvider, (_, d) => seen.add(d), fireImmediately: true);
        expect(seen, [sun]);

        async.elapse(const Duration(seconds: 29));
        expect(seen, [sun], reason: 'not yet midnight');
        async.elapse(const Duration(seconds: 3));
        expect(seen, [sun, DayKey(2026, 10, 12)]);

        async.elapse(const Duration(hours: 24));
        expect(seen.last, DayKey(2026, 10, 13));
      });
    });

    test('refresh picks up a clock that changed while no timer ran', () {
      var now = DateTime(2026, 10, 11, 12);
      final c = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      expect(c.read(todayProvider), sun);
      now = DateTime(2026, 10, 14, 8);
      c.read(todayProvider.notifier).refresh();
      expect(c.read(todayProvider), DayKey(2026, 10, 14));
    });

    test('refresh on the same day changes nothing', () {
      final now = DateTime(2026, 10, 11, 12);
      final c = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      var notified = 0;
      c.listen(todayProvider, (_, _) => notified++);
      c.read(todayProvider.notifier).refresh();
      expect(notified, 0);
    });

    test('the shown day follows today until a day is picked', () {
      var now = DateTime(2026, 10, 11, 12);
      final c = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      expect(c.read(shownDayProvider), sun);
      now = DateTime(2026, 10, 12, 1);
      c.read(todayProvider.notifier).refresh();
      expect(c.read(shownDayProvider), DayKey(2026, 10, 12));
      c.read(selectedDayProvider.notifier).select(fri);
      c.read(todayProvider.notifier).refresh();
      expect(c.read(shownDayProvider), fri);
      c.read(selectedDayProvider.notifier).select(null);
      expect(c.read(shownDayProvider), DayKey(2026, 10, 12));
    });
  });

  group('settings', () {
    test('a change is kept in memory and on disk', () async {
      final c = await makeContainer();
      await c
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(streakThreshold: 80, theme: ThemeChoice.dark),
          );
      expect(c.read(settingsProvider).streakThreshold, 80);
      expect(
        Settings.read(c.read(sharedPrefsProvider)).theme,
        ThemeChoice.dark,
      );
    });

    test('starts from what is stored', () async {
      final c = await makeContainer(prefs: {'streakThreshold': 40});
      expect(c.read(settingsProvider).streakThreshold, 40);
    });
  });

  group('stored data reaches the screens', () {
    test(
      'a write rebuilds the ledger and the Today view without being asked',
      () async {
        final c = await makeContainer(clock: () => DateTime(2026, 10, 5, 9));
        final repo = c.read(repositoryProvider);
        expect((await c.read(ledgerProvider.future)).habits, isEmpty);

        await repo.addHabit(habit('a'));
        final l1 = await c.read(ledgerProvider.future);
        expect(l1.habits.map((h) => h.id), ['a']);
        expect(
          c.read(todayViewProvider).requireValue.toDo.map((r) => r.habit.id),
          ['a'],
        );

        await repo.setEntry(entry('a', mon));
        await c.read(ledgerProvider.future);
        final v = c.read(todayViewProvider).requireValue;
        expect(v.toDo, isEmpty);
        expect(v.finished.map((r) => r.habit.id), ['a']);
        expect(v.summary.done, 1);
      },
    );

    test('the view follows the picked day and the search text', () async {
      final c = await makeContainer(clock: () => DateTime(2026, 10, 11, 9));
      final repo = c.read(repositoryProvider);
      await repo.addHabit(habit('run'));
      await repo.addHabit(habit('read'));
      await repo.setEntry(entry('run', mon));
      await c.read(ledgerProvider.future);

      c.read(selectedDayProvider.notifier).select(mon);
      expect(
        c.read(todayViewProvider).requireValue.finished.map((r) => r.habit.id),
        ['run'],
      );
      c.read(searchQueryProvider.notifier).set('read');
      final v = c.read(todayViewProvider).requireValue;
      expect(v.toDo.map((r) => r.habit.id), ['read']);
      expect(v.finished, isEmpty);
    });

    test('the streak threshold setting changes the day summary', () async {
      final c = await makeContainer(clock: () => DateTime(2026, 10, 5, 9));
      final repo = c.read(repositoryProvider);
      for (final id in ['a', 'b']) {
        await repo.addHabit(habit(id));
      }
      await repo.setEntry(entry('a', mon));
      await c.read(ledgerProvider.future);
      expect(
        c.read(todayViewProvider).requireValue.summary.status.name,
        'missed',
      ); // 1 of 2 = 50% < 60%
      await c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(streakThreshold: 50));
      expect(
        c.read(todayViewProvider).requireValue.summary.status.name,
        'good',
      );
    });
  });
}
