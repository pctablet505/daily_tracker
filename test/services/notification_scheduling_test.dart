import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

/// The real scheduler and the notification buttons, run against the plugin's
/// own Dart code with only the Android side of its channel answered here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezone = MethodChannel('flutter_timezone');
  late List<MethodCall> calls;
  late List<Map<String, Object?>> pending;
  late String zone;

  setUp(() {
    // The notification handlers read the App Lock setting; with none stored it is off.
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    pending = [];
    zone = 'Europe/London';
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => true,
        'pendingNotificationRequests' => pending,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(timezone, (_) async => zone);
    addTearDown(() {
      messenger.setMockMethodCallHandler(plugin, null);
      messenger.setMockMethodCallHandler(timezone, null);
    });
  });

  List<Map<Object?, Object?>> scheduled() => [
    for (final c in calls)
      if (c.method == 'zonedSchedule') c.arguments as Map<Object?, Object?>,
  ];
  List<Object?> cancelled() => [
    for (final c in calls)
      if (c.method == 'cancel') (c.arguments as Map<Object?, Object?>)['id'],
  ];
  Map<String, Object?> shown(int id, String payload) => {
    'id': id,
    'title': 't',
    'body': 'b',
    'payload': payload,
  };

  test('each re-plan schedules in the time zone the phone is in now', () async {
    final s = LocalNotificationsScheduler(appLockOn: () async => false);
    await s.init();
    zone = 'Asia/Kolkata';
    final when = DateTime.now().add(const Duration(days: 1));
    await s.replaceAll([
      PlannedReminder(
        id: 7,
        when: when,
        kind: ReminderKind.habit,
        title: 't',
        body: 'b',
        habitId: 'a',
        forDay: DayKey.fromDate(when),
      ),
    ]);
    expect(scheduled().single['timeZoneName'], 'Asia/Kolkata');
  });

  test(
    'a re-plan cancels the old plan and the snoozes it must drop, nothing else',
    () async {
      pending = [
        shown(3, 'habit:a@2026-10-11'),
        shown(snoozeIdBase + 3, 'habit:a@2026-10-11'),
        shown(snoozeIdBase + 4, 'habit:b@2026-10-11'),
      ];
      final s = LocalNotificationsScheduler(appLockOn: () async => false);
      await s.init();
      await s.replaceAll(
        const [],
        keepSnooze: (payload) => payload == 'habit:a@2026-10-11',
      );
      expect(cancelled(), [3, snoozeIdBase + 4]);
    },
  );

  test('with App Lock on, a re-plan cancels the snoozes too: they were posted '
      'with buttons and show the habit on the lock screen', () async {
    pending = [
      shown(3, 'habit:a@2026-10-11'),
      shown(snoozeIdBase + 3, 'habit:a@2026-10-11'),
    ];
    final s = LocalNotificationsScheduler(appLockOn: () async => true);
    await s.init();
    await s.replaceAll(const [], keepSnooze: (_) => true);
    expect(cancelled(), [3, snoozeIdBase + 3]);
  });

  group('In 1 hour', () {
    setUp(() async {
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('dt_snooze_');
      addTearDown(() => dir.delete(recursive: true));
      await databaseFactory.setDatabasesPath(dir.path);
      final db = await openAppDatabase(
        databaseFactoryFfi,
        p.join(dir.path, databaseFileName),
        singleInstance: false,
      );
      await HabitRepository(db).addHabit(habit('a'));
      await db.close();
    });

    Future<int> snooze(int id) async {
      await notificationBackgroundHandler(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          id: id,
          actionId: 'snooze',
          payload: 'habit:a@2026-10-11',
        ),
      );
      return scheduled().single['id']! as int;
    }

    test('steps past an id that another reminder\'s snooze holds', () async {
      pending = [shown(snoozeIdBase + 5, 'habit:b@2026-10-11')];
      expect(await snooze(5), snoozeIdBase + 6);
    });

    test('snoozing the same reminder again replaces its snooze', () async {
      pending = [shown(snoozeIdBase + 5, 'habit:a@2026-10-11')];
      expect(await snooze(5), snoozeIdBase + 5);
    });

    test('at the top of the id range it wraps to the start of the snooze '
        'range, since Android ids are 32-bit', () async {
      pending = [shown(0x7fffffff, 'habit:b@2026-10-11')];
      expect(await snooze(snoozeIdBase - 1), snoozeIdBase);
    });
  });
}
