import 'dart:async';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/services/reminder_sync.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

final class FakeScheduler implements ReminderScheduler {
  bool granted = true;
  final plans = <List<PlannedReminder>>[];
  final tapController = StreamController<String>.broadcast();
  var permissionRequests = 0;

  @override
  Future<void> init() async {}
  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> plan) async => plans.add(plan);
  @override
  Stream<String> get taps => tapController.stream;
  @override
  Future<String?> launchPayload() async => null;
}

void main() {
  sqfliteFfiInit();
  late FakeScheduler scheduler;
  late ProviderContainer c;
  var now = DateTime(2026, 10, 11, 6);

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  setUp(() async {
    now = DateTime(2026, 10, 11, 6);
    scheduler = FakeScheduler();
    SharedPreferences.setMockInitialValues({});
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        clockProvider.overrideWithValue(() => now),
        reminderSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
  });

  test('schedules the plan once data has loaded', () async {
    final repo = c.read(repositoryProvider);
    await repo.addHabit(habit('a').copyWith(reminderMinutes: () => 8 * 60));
    c.read(reminderSyncProvider);
    await settle();
    expect(scheduler.plans, isNotEmpty);
    expect(scheduler.plans.last.first.habitId, 'a');
    expect(scheduler.plans.last.length, ReminderSync.horizonDays);
  });

  test('a burst of changes causes one rescheduling, not many', () async {
    final repo = c.read(repositoryProvider);
    c.read(reminderSyncProvider);
    await settle();
    final before = scheduler.plans.length;
    for (var i = 0; i < 5; i++) {
      await repo.addHabit(habit('h$i').copyWith(reminderMinutes: () => 8 * 60));
    }
    await settle();
    expect(scheduler.plans.length - before, lessThanOrEqualTo(2));
    expect(scheduler.plans.last.map((r) => r.habitId).toSet().length, 5);
  });

  test(
    'finishing a habit today takes today\'s reminder out of the plan',
    () async {
      final repo = c.read(repositoryProvider);
      await repo.addHabit(
        habit('a', created: sun).copyWith(reminderMinutes: () => 20 * 60),
      );
      c.read(reminderSyncProvider);
      await settle();
      expect(scheduler.plans.last.first.when, DateTime(2026, 10, 11, 20));
      await repo.setEntry(entry('a', sun));
      await settle();
      expect(scheduler.plans.last.first.when, DateTime(2026, 10, 12, 20));
    },
  );

  test('without notification permission nothing is scheduled', () async {
    scheduler.granted = false;
    await c
        .read(repositoryProvider)
        .addHabit(habit('a').copyWith(reminderMinutes: () => 8 * 60));
    c.read(reminderSyncProvider);
    await settle();
    expect(scheduler.plans, isEmpty);
  });

  test('turning reminders off clears what was scheduled', () async {
    await c
        .read(repositoryProvider)
        .addHabit(habit('a').copyWith(reminderMinutes: () => 8 * 60));
    c.read(reminderSyncProvider);
    await settle();
    await c
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(remindersOn: false));
    await settle();
    expect(scheduler.plans.last, isEmpty);
  });

  test(
    'resync schedules again right away, for when permission was just granted',
    () async {
      scheduler.granted = false;
      await c
          .read(repositoryProvider)
          .addHabit(habit('a').copyWith(reminderMinutes: () => 8 * 60));
      final sync = c.read(reminderSyncProvider);
      await settle();
      expect(scheduler.plans, isEmpty);
      scheduler.granted = true;
      await sync.resync();
      expect(scheduler.plans.last, isNotEmpty);
    },
  );
}
