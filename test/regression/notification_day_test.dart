// Regression tests for defects found in review. Each test states the behaviour the app
// promises; a red result is a finding.
import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

void main() {
  sqfliteFfiInit();

  test('Done on a reminder that quiet hours pushed past midnight marks the day it was for', () async {
    databaseFactory = databaseFactoryFfi;
    // App Lock off: with it on, the button would refuse.
    SharedPreferences.setMockInitialValues({});
    final path = p.join(await getDatabasesPath(), databaseFileName);
    if (File(path).existsSync()) File(path).deleteSync();
    addTearDown(() {
      if (File(path).existsSync()) File(path).deleteSync();
    });

    final today = DayKey.fromDate(DateTime.now());
    final yesterday = today.addDays(-1);
    final read = habit(
      'read',
      created: yesterday.addDays(-7),
    ).copyWith(reminderMinutes: () => 23 * 60);

    // The plan made yesterday evening: 23:00 falls in quiet hours 22:00-07:00.
    final plan = planReminders(
      Ledger(habits: [read], entries: const []),
      settings: const Settings(
        eveningCheckInOn: false,
        quietHoursOn: true,
        quietStartMinutes: 22 * 60,
        quietEndMinutes: 7 * 60,
      ),
      now: DateTime(yesterday.year, yesterday.month, yesterday.day, 21),
      horizonDays: 1,
    );
    expect(plan.single.when, DateTime(today.year, today.month, today.day, 7));
    expect(plan.single.payload, 'habit:read@$yesterday');

    final db = await openAppDatabase(
      databaseFactoryFfi,
      path,
      singleInstance: false,
    );
    await HabitRepository(db).addHabit(read);
    await db.close();

    // The user taps Done on that 07:00 notification this morning.
    await notificationBackgroundHandler(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: plan.single.id,
        actionId: 'done',
        payload: plan.single.payload,
      ),
    );

    final check = await openAppDatabase(
      databaseFactoryFfi,
      path,
      singleInstance: false,
    );
    final days = [
      for (final e in await HabitRepository(check).entries()) e.day,
    ];
    await check.close();
    expect(days, [
      yesterday,
    ], reason: 'the reminder was for $yesterday; Done marked $days');
  });
}
