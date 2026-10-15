import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
}
