import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Runs on a real Android device or emulator. The Done button on a reminder
/// runs the same code the phone runs when the app is closed, while the app's own
/// database connection may be open: pressing it must not break that connection.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'pressing Done in a notification leaves the app database usable',
    (tester) async {
      await tester.runAsync(() async {
        final path = p.join(await getDatabasesPath(), databaseFileName);
        await deleteDatabase(path);
        final appDb = await openAppDatabase(databaseFactory, path);
        final repo = HabitRepository(appDb);
        final today = DayKey.fromDate(DateTime.now());
        final habit = await repo.addHabit(
          Habit(id: 'it-read', name: 'Read', createdDay: today),
        );

        await notificationBackgroundHandler(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            id: 7,
            actionId: 'done',
            payload: 'habit:${habit.id}',
          ),
        );

        // The app's own connection still works, and sees what the button wrote.
        final entries = await repo.entries(
          habitId: habit.id,
          from: today,
          to: today,
        );
        expect(entries, hasLength(1));
        expect(entries.single.state, EntryState.done);
        expect(await repo.markSeen(today), isA<bool>());

        await appDb.close();
        await deleteDatabase(path);
      });
    },
  );
}
