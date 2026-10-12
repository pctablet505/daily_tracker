import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a real Android device or emulator, with no fakes: a reminder that is
/// scheduled must come out of the phone's alarm system as a visible notification.
///
/// Needs the notification permission:
///   adb shell pm grant com.dailytracker.daily_tracker.debug android.permission.POST_NOTIFICATIONS
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a scheduled reminder shows up in the notification shade', (
    tester,
  ) async {
    final scheduler = LocalNotificationsScheduler();
    await tester.runAsync(scheduler.init);
    expect(
      await tester.runAsync(scheduler.hasPermission),
      isTrue,
      reason: 'grant POST_NOTIFICATIONS before running this test',
    );

    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;

    final reminder = PlannedReminder(
      id: 4242,
      when: DateTime.now().add(const Duration(seconds: 5)),
      kind: ReminderKind.habit,
      title: 'Integration test reminder',
      body: 'If you can read this, scheduling works.',
      habitId: 'it',
      markable: true,
    );
    await tester.runAsync(() => scheduler.replaceAll([reminder]));

    final started = DateTime.now();
    var shown = false;
    await tester.runAsync(() async {
      while (DateTime.now().difference(started) < const Duration(minutes: 4)) {
        final active = await android.getActiveNotifications();
        if (active.any((n) => n.id == reminder.id)) {
          shown = true;
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    });
    final took = DateTime.now().difference(started);
    // ignore: avoid_print
    print('reminder shown=$shown after ${took.inSeconds}s');
    expect(shown, isTrue, reason: 'no notification appeared within 4 minutes');
    await tester.runAsync(() => scheduler.replaceAll(const []));
    await android.cancel(id: reminder.id);
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('a snoozed reminder survives the app re-planning its reminders', (
    tester,
  ) async {
    final scheduler = LocalNotificationsScheduler();
    await tester.runAsync(scheduler.init);
    final plugin = FlutterLocalNotificationsPlugin();

    await tester.runAsync(() async {
      await scheduler.replaceAll(const []);
      await notificationBackgroundHandler(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          id: 5,
          actionId: 'snooze',
          payload: 'habit:unknown@2026-10-11',
        ),
      );
      var pending = await plugin.pendingNotificationRequests();
      expect(pending.map((n) => n.id), [snoozeIdFor(5)]);

      // The app re-plans (it does on every open and every change).
      await scheduler.replaceAll([
        PlannedReminder(
          id: 1,
          when: DateTime.now().add(const Duration(days: 1)),
          kind: ReminderKind.habit,
          title: 'Planned',
          body: 'x',
          habitId: 'unknown',
        ),
      ]);
      pending = await plugin.pendingNotificationRequests();
      expect(pending.map((n) => n.id).toSet(), {1, snoozeIdFor(5)});

      await scheduler.replaceAll(const []);
      pending = await plugin.pendingNotificationRequests();
      expect(pending.map((n) => n.id), [snoozeIdFor(5)]);
      await plugin.cancelAllPendingNotifications();
    });
  });
}
