import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/settings.dart';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

/// Preferences in memory whose next write fails once (a full disk).
final class _FlakyPrefs extends Fake implements SharedPreferences {
  final _values = <String, Object>{};
  bool failNext = false;

  Future<bool> _set(String key, Object value) async {
    if (failNext) {
      failNext = false;
      throw StateError('disk full');
    }
    _values[key] = value;
    return true;
  }

  @override
  Object? get(String key) => _values[key];
  @override
  Future<bool> setBool(String key, bool value) => _set(key, value);
  @override
  Future<bool> setInt(String key, int value) => _set(key, value);
  @override
  Future<bool> setString(String key, String value) => _set(key, value);
}

void main() {
  sqfliteFfiInit();

  Future<ProviderContainer> makeContainer({
    DateTime Function()? clock,
    Map<String, Object> prefs = const {},
    Directory? photos,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        // The Today view checks which photo files exist; none do here.
        photoStoreProvider.overrideWithValue(
          DiskPhotoStore(photos ?? Directory('/definitely/not/here')),
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

    test('a failed write does not stop the writes after it', () async {
      final prefs = _FlakyPrefs();
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      final settings = c.read(settingsProvider.notifier);

      prefs.failNext = true;
      await expectLater(
        settings.update((s) => s.copyWith(remindersOn: false)),
        throwsStateError,
      );
      await settings.update((s) => s.copyWith(theme: ThemeChoice.dark));
      expect(Settings.read(prefs).theme, ThemeChoice.dark);
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

    test(
      'the Today view counts only the photos that are on the phone',
      () async {
        final dir = await Directory.systemTemp.createTemp('dt_prov_photos_');
        addTearDown(() => dir.delete(recursive: true));
        File('${dir.path}/here.jpg').writeAsBytesSync([1]);
        final c = await makeContainer(
          clock: () => DateTime(2026, 10, 11, 9),
          photos: dir,
        );
        final repo = c.read(repositoryProvider);
        await repo.addHabit(habit('p', logType: LogType.photo));
        // After a restore the entry is there but its photo file is not.
        await repo.setEntry(
          entry('p', mon).copyWith(photoPath: () => 'here.jpg'),
        );
        await repo.setEntry(
          entry('p', tue).copyWith(photoPath: () => 'gone.jpg'),
        );
        await c.read(ledgerProvider.future);
        final v = c.read(todayViewProvider).requireValue;
        expect([...v.toDo, ...v.finished].single.photoCount, 1);
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

    test('the Today view keeps its last value while a write reloads', () async {
      final c = await makeContainer(clock: () => DateTime(2026, 10, 11, 9));
      final repo = c.read(repositoryProvider);
      await repo.addHabit(habit('run'));
      await c.read(ledgerProvider.future);
      final seen = <int?>[];
      c.listen(
        todayViewProvider,
        (_, next) => seen.add(next.value?.summary.done),
        fireImmediately: true,
      );

      await repo.setEntry(entry('run', sun));
      await c.read(ledgerProvider.future);
      await c.pump();
      // The screens compare the day before and after a write; a gap in
      // between would show a spinner and hide the change.
      expect(seen, isNot(contains(null)));
      expect(seen.last, 1);
    });

    test('a picked past day that was missed shows no streak', () async {
      final c = await makeContainer(clock: () => DateTime(2026, 10, 11, 9));
      final repo = c.read(repositoryProvider);
      await repo.addHabit(habit('run'));
      await repo.setEntry(entry('run', mon));
      await repo.setEntry(entry('run', tue));
      await c.read(ledgerProvider.future);

      // Wednesday is over and was not done; it is not still open like today.
      c.read(selectedDayProvider.notifier).select(wed);
      expect(c.read(todayViewProvider).requireValue.toDo.single.streak, 0);
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
