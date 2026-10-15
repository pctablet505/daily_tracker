import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/fixtures.dart';

/// The phone's notification system: remembers what was scheduled.
final class _Plugin extends Fake implements FlutterLocalNotificationsPlugin {
  final scheduled = <AndroidNotificationDetails>[];

  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => const [];

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async => scheduled.add(notificationDetails.android!);
}

final _reminder = PlannedReminder(
  id: 7,
  when: DateTime(2026, 10, 12, 7, 30),
  kind: ReminderKind.habit,
  title: 'Go for a run',
  body: 'Time for it',
  habitId: 'run',
  forDay: DayKey(2026, 10, 12),
  markable: true,
);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('reminders scheduled', () {
    test(
      'with App Lock on carry no buttons and show nothing on the lock screen',
      () async {
        final plugin = _Plugin();
        await LocalNotificationsScheduler(
          plugin: plugin,
          appLockOn: () async => true,
        ).replaceAll([_reminder]);
        final d = plugin.scheduled.single;
        expect(d.actions, isNull);
        expect(d.visibility, NotificationVisibility.secret);
      },
    );

    test('with App Lock off offer Done and "In 1 hour"', () async {
      final plugin = _Plugin();
      await LocalNotificationsScheduler(
        plugin: plugin,
        appLockOn: () async => false,
      ).replaceAll([_reminder]);
      final d = plugin.scheduled.single;
      expect([for (final a in d.actions!) a.id], ['done', 'snooze']);
      expect(d.visibility, NotificationVisibility.private);
    });

    test('follow the App Lock setting the app stored', () async {
      SharedPreferences.setMockInitialValues({'lockOn': true});
      final plugin = _Plugin();
      await LocalNotificationsScheduler(plugin: plugin).replaceAll([_reminder]);
      expect(plugin.scheduled.single.actions, isNull);
    });
  });

  group('a notification button', () {
    sqfliteFfiInit();
    late String path;

    setUp(() async {
      // Its own folder: other test files use the default one at the same time.
      final dir = Directory.systemTemp.createTempSync('notifications_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(dir.path);
      path = p.join(await getDatabasesPath(), databaseFileName);
      final today = DayKey.fromDate(DateTime.now());
      final db = await openAppDatabase(
        databaseFactoryFfi,
        path,
        singleInstance: false,
      );
      await HabitRepository(db)
          .addHabit(habit('run', created: today.addDays(-3)));
      await db.close();
    });

    Future<int> entries() async {
      final db = await openAppDatabase(
        databaseFactoryFfi,
        path,
        singleInstance: false,
      );
      final n = (await HabitRepository(db).entries()).length;
      await db.close();
      return n;
    }

    Future<void> pressDone() => notificationBackgroundHandler(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: 7,
        actionId: 'done',
        payload: 'habit:run@${DayKey.fromDate(DateTime.now())}',
      ),
    );

    test(
      'pressed with App Lock on (an older notification) changes nothing',
      () async {
        SharedPreferences.setMockInitialValues({'lockOn': true});
        await pressDone();
        expect(await entries(), 0);
      },
    );

    test('pressed with App Lock off marks the habit done', () async {
      SharedPreferences.setMockInitialValues({'lockOn': false});
      await pressDone();
      expect(await entries(), 1);
    });
  });
}
