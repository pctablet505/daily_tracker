import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/day_key.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../logic/logging.dart';
import 'reminder_plan.dart';

/// What the app needs from the phone's notification system. The real one is
/// [LocalNotificationsScheduler]; tests use a fake.
abstract interface class ReminderScheduler {
  Future<void> init();

  /// Whether notifications may be shown (Android 13 and newer ask for this).
  Future<bool> hasPermission();

  /// Shows the system permission prompt if needed and returns whether it is granted.
  Future<bool> requestPermission();

  /// Cancels every pending reminder and schedules [plan].
  Future<void> replaceAll(List<PlannedReminder> plan);

  /// The payload of each notification the user taps while the app is running.
  Stream<String> get taps;

  /// The payload of the notification that started the app, if one did.
  Future<String?> launchPayload();
}

const _doneAction = AndroidNotificationAction('done', 'Done', showsUserInterface: false, cancelNotification: true);
const _snoozeAction = AndroidNotificationAction('snooze', 'In 1 hour', showsUserInterface: false, cancelNotification: true);

AndroidNotificationDetails _androidDetails(ReminderKind kind, {bool withActions = false}) {
  final habit = kind == ReminderKind.habit;
  return AndroidNotificationDetails(
    habit ? 'habit_reminders' : 'check_in',
    habit ? 'Habit reminders' : 'Evening check-in',
    channelDescription: habit
        ? 'A nudge at the time you set for a habit'
        : 'A daily prompt to log slips on the habits you stay clear of',
    importance: habit ? Importance.high : Importance.defaultImportance,
    priority: habit ? Priority.high : Priority.defaultPriority,
    icon: 'ic_notification',
    actions: withActions ? const [_doneAction, _snoozeAction] : null,
  );
}

const _initSettings = InitializationSettings(android: AndroidInitializationSettings('ic_notification'));

final class LocalNotificationsScheduler implements ReminderScheduler {
  LocalNotificationsScheduler([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();

  @override
  Stream<String> get taps => _taps.stream;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      // Without the real zone, UTC would shift every reminder by the offset; log it loudly.
      debugPrint('Could not read the time zone, reminders may be off: $e');
    }
    await _plugin.initialize(
      settings: _initSettings,
      onDidReceiveNotificationResponse: (r) {
        final payload = r.payload;
        if (payload != null) _taps.add(payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
  }

  @override
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return d != null && d.didNotificationLaunchApp ? d.notificationResponse?.payload : null;
  }

  @override
  Future<bool> hasPermission() async => await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async {
    if (await hasPermission()) return true;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> plan) async {
    await _plugin.cancelAllPendingNotifications();
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.when, tz.local),
        notificationDetails: NotificationDetails(android: _androidDetails(r.kind, withActions: r.markable)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.payload,
      );
    }
  }
}

/// Marks a tick habit done for [day] straight in the database. Used by the
/// notification's Done button, which runs without the app open.
Future<bool> markDoneFromNotification(Database db, String habitId, DayKey day, DateTime now) async {
  final repo = HabitRepository(db);
  final habit = (await repo.habits()).where((h) => h.id == habitId).firstOrNull;
  if (habit == null || habit.logType != LogType.tick) return false;
  final existing = (await repo.entries(habitId: habitId, from: day, to: day)).firstOrNull;
  if (existing?.state == EntryState.done) return true;
  final next = tickEntry(habit, day, existing, now);
  if (next == null) return false;
  await repo.setEntry(next);
  return true;
}

/// Runs in a separate isolate when a notification button is pressed with the app closed.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  final payload = r.payload;
  if (payload == null || !payload.startsWith('habit:')) return;
  final habitId = payload.substring('habit:'.length);
  try {
    if (r.actionId == 'done') {
      final dir = await getDatabasesPath();
      final db = await openAppDatabase(databaseFactory, p.join(dir, databaseFileName));
      try {
        await markDoneFromNotification(db, habitId, DayKey.fromDate(DateTime.now()), DateTime.now());
      } finally {
        await db.close();
      }
    } else if (r.actionId == 'snooze') {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(settings: _initSettings);
      await plugin.zonedSchedule(
        id: r.id ?? DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
        title: 'Reminder',
        body: 'You snoozed this one.',
        scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(hours: 1)),
        notificationDetails: NotificationDetails(android: _androidDetails(ReminderKind.habit, withActions: true)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  } catch (e) {
    debugPrint('Notification action failed: $e');
  }
}
