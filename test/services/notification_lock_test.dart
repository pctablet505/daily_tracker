import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

/// The notification buttons run in one isolate that stays alive while the app
/// changes settings in its own. The settings store is the phone's, answered
/// here on its channel, so each isolate sees only what it reads from it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final stored = <String, Object>{};
  late String path;

  setUp(() async {
    stored
      ..clear()
      ..['flutter.lockOn'] = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => switch (call.method) {
            'getAll' => Map.of(stored),
            _ => null,
          },
        );
    final dir = Directory.systemTemp.createTempSync('notification_lock_test');
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
    for (final id in ['run', 'walk']) {
      await HabitRepository(db).addHabit(habit(id, created: today.addDays(-3)));
    }
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

  Future<void> pressDone(String habitId) => notificationBackgroundHandler(
    NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      id: 7,
      actionId: 'done',
      payload: 'habit:$habitId@${DayKey.fromDate(DateTime.now())}',
    ),
  );

  test('a button pressed after App Lock was turned on in the app changes '
      'nothing, though an earlier press ran with it off', () async {
    await pressDone('run');
    expect(await entries(), 1);
    stored['flutter.lockOn'] = true;
    await pressDone('walk');
    expect(await entries(), 1);
  });

  test('a re-plan in the app keeps a setting written while it runs', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // The phone's store answers in order: a read sees what was written before
    // it was asked, and takes a while.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') {
          final snapshot = Map.of(stored);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return snapshot;
        }
        if (call.method.startsWith('set')) {
          final a = call.arguments as Map<Object?, Object?>;
          stored[a['key']! as String] = a['value']!;
        }
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'Europe/London',
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_timezone'),
        null,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final replan = LocalNotificationsScheduler(plugin: _NoReminders())
        .replaceAll(const []);
    // An automatic backup storing its record meanwhile.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await prefs.setString('cloud.file', 'file7@1');
    await replan;
    expect(stored['flutter.cloud.file'], 'file7@1');
    expect(prefs.getString('cloud.file'), 'file7@1');
  });
}

final class _NoReminders extends Fake
    implements FlutterLocalNotificationsPlugin {
  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => const [];
}
