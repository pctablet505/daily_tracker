import 'dart:async';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/day_key.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../logic/logging.dart';
import '../state/settings.dart';
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
  Future<void> replaceAll(
    List<PlannedReminder> plan, {
    bool Function(String? payload)? keepSnooze,
  });

  /// The payload of each notification the user taps while the app is running.
  Stream<String> get taps;

  /// The payload of the notification that started the app, if one did.
  Future<String?> launchPayload();
}

const _doneAction = AndroidNotificationAction(
  'done',
  'Done',
  showsUserInterface: false,
  cancelNotification: true,
);
const _snoozeAction = AndroidNotificationAction(
  'snooze',
  'In 1 hour',
  showsUserInterface: false,
  cancelNotification: true,
);

AndroidNotificationDetails _androidDetails(
  ReminderKind kind, {
  bool withActions = false,
  bool appLocked = false,
}) {
  final habit = kind == ReminderKind.habit;
  return AndroidNotificationDetails(
    habit ? 'habit_reminders' : 'check_in',
    habit ? 'Habit reminders' : 'Evening check-in',
    channelDescription: habit
        ? 'A nudge at the time you set for a habit'
        : 'A daily prompt to log slips on the habits you stay clear of',
    importance: habit ? Importance.high : Importance.defaultImportance,
    priority: habit ? Priority.high : Priority.defaultPriority,
    // With App Lock on, nothing of a reminder shows on the phone's lock screen,
    // and no button can change a habit without the PIN.
    visibility: appLocked
        ? NotificationVisibility.secret
        : NotificationVisibility.private,
    icon: 'ic_notification',
    actions: withActions && !appLocked
        ? const [_doneAction, _snoozeAction]
        : null,
  );
}

const _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('ic_notification'),
);

Future<void> _refreshLocalTimezone() async {
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  } catch (e) {
    // Without the real zone, UTC would shift every reminder by the offset; log it loudly.
    debugPrint('Could not read the time zone, reminders may be off: $e');
  }
}

final class LocalNotificationsScheduler implements ReminderScheduler {
  LocalNotificationsScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    this._appLockOn = _readAppLockOn,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Future<bool> Function() _appLockOn;
  final _taps = StreamController<String>.broadcast();

  @override
  Stream<String> get taps => _taps.stream;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _refreshLocalTimezone();
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
    return d != null && d.didNotificationLaunchApp
        ? d.notificationResponse?.payload
        : null;
  }

  @override
  Future<bool> hasPermission() async =>
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async {
    if (await hasPermission()) return true;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> replaceAll(
    List<PlannedReminder> plan, {
    bool Function(String? payload)? keepSnooze,
  }) async {
    await _refreshLocalTimezone();
    // Snoozed reminders are not part of the plan and must outlive a re-plan
    // unless their habit was completed, deleted, or reminders were turned off.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (!isSnoozeId(pending.id) ||
          (keepSnooze != null && !keepSnooze(pending.payload))) {
        await _plugin.cancel(id: pending.id);
      }
    }
    final appLocked = await _appLockOn();
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.when, tz.local),
        notificationDetails: NotificationDetails(
          android: _androidDetails(
            r.kind,
            withActions: r.markable,
            appLocked: appLocked,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.payload,
      );
    }
  }
}

/// Marks a tick habit done for [day] straight in the database. Used by the
/// notification's Done button, which runs without the app open.
Future<bool> markDoneFromNotification(
  Database db,
  String habitId,
  DayKey day,
  DateTime now,
) async {
  final repo = HabitRepository(db);
  final habit = (await repo.habits()).where((h) => h.id == habitId).firstOrNull;
  if (habit == null ||
      habit.logType != LogType.tick ||
      habit.tracksSlips ||
      !habit.isActiveOn(day)) {
    return false;
  }
  final existing = (await repo.entries(
    habitId: habitId,
    from: day,
    to: day,
  )).firstOrNull;
  if (existing?.state == EntryState.done) return true;
  final next = tickEntry(habit, day, existing, now);
  if (next == null) return false;
  await repo.setEntry(next);
  return true;
}

/// Whether App Lock is on, read from the stored settings: the notification
/// buttons run in their own isolate, without the app's state.
Future<bool> _readAppLockOn() async =>
    Settings.read(await SharedPreferences.getInstance()).lockOn;

/// A snoozed reminder gets an id in its own range so a re-plan leaves it alone.
bool isSnoozeId(int id) => id >= snoozeIdBase;
int snoozeIdFor(int id) => isSnoozeId(id) ? id : snoozeIdBase + id;

/// The app listens on this port name; a notification button sends to it after
/// writing, so a screen that is open refreshes at once.
const dataChangedPortName = 'daily_tracker/data-changed';

void announceDataChanged() =>
    IsolateNameServer.lookupPortByName(dataChangedPortName)?.send(null);

/// Runs in a separate isolate when a notification button is pressed, whether or
/// not the app is open.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  final target = r.payload == null ? null : parseHabitPayload(r.payload!);
  if (target == null) return;
  final habitId = target.habitId;
  try {
    // Buttons on a notification posted before App Lock was turned on.
    if (await _readAppLockOn()) return;
    if (r.actionId == 'done') {
      final dir = await getDatabasesPath();
      // Its own connection: closing the app's shared one would break the open app.
      final db = await openAppDatabase(
        databaseFactory,
        p.join(dir, databaseFileName),
        singleInstance: false,
      );
      try {
        await markDoneFromNotification(
          db,
          habitId,
          target.day ?? DayKey.fromDate(DateTime.now()),
          DateTime.now(),
        );
      } finally {
        await db.close();
      }
      announceDataChanged();
    } else if (r.actionId == 'snooze') {
      tzdata.initializeTimeZones();
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: _initSettings,
        onDidReceiveBackgroundNotificationResponse:
            notificationBackgroundHandler,
      );
      final dir = await getDatabasesPath();
      final db = await openAppDatabase(
        databaseFactory,
        p.join(dir, databaseFileName),
        singleInstance: false,
      );
      final String? name;
      try {
        name = (await HabitRepository(
          db,
        ).habits()).where((h) => h.id == habitId).firstOrNull?.name;
      } finally {
        await db.close();
      }
      final pending = await plugin.pendingNotificationRequests();
      var snoozeId = snoozeIdFor(
        r.id ?? DateTime.now().millisecondsSinceEpoch & 0xffff,
      );
      while (pending.any((p) => p.id == snoozeId && p.payload != r.payload)) {
        // Android notification ids are 32-bit.
        snoozeId = snoozeId == 0x7fffffff ? snoozeIdBase : snoozeId + 1;
      }
      await plugin.zonedSchedule(
        id: snoozeId,
        title: name ?? 'Reminder',
        body: 'You snoozed this one.',
        scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(hours: 1)),
        notificationDetails: NotificationDetails(
          android: _androidDetails(ReminderKind.habit, withActions: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.payload,
      );
    }
  } catch (e) {
    debugPrint('Notification action failed: $e');
  }
}
