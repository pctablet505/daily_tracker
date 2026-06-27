import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/services/notification/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');

  final store = <String, Object>{};
  final calls = <MethodCall>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getAll':
        case 'getAllWithParameters':
          return Map<String, Object>.from(store);
        case 'setString':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as String;
          return true;
        case 'setBool':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as bool;
          return true;
        case 'setInt':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as int;
          return true;
        case 'setDouble':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as double;
          return true;
        case 'remove':
          final args = call.arguments as Map<dynamic, dynamic>;
          store.remove(args['key'] as String);
          return true;
        case 'clear':
          store.clear();
          return true;
        case 'clearWithParameters':
          final args = call.arguments as Map<dynamic, dynamic>;
          final prefix = args['prefix'] as String? ?? '';
          store.removeWhere((key, _) => key.startsWith(prefix));
          return true;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'createNotificationChannel':
          return null;
        case 'canScheduleExactNotifications':
          return true;
        case 'zonedSchedule':
        case 'cancel':
          return null;
        default:
          return null;
      }
    });
  });

  setUp(() async {
    store.clear();
    calls.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
  });

  group('ReminderService.scheduleTaskReminder', () {
    test('schedules a zoned notification for a future task reminder', () async {
      final service = ReminderService();
      final reminderTime = DateTime.now().add(const Duration(hours: 2));
      final task = TaskModel(
        id: 'task-123',
        title: 'Buy milk',
        createdAt: DateTime(2024, 6, 15),
        updatedAt: DateTime(2024, 6, 15),
        reminderTime: reminderTime,
      );

      await service.scheduleTaskReminder(task);

      final zonedScheduleCalls =
          calls.where((c) => c.method == 'zonedSchedule').toList();
      expect(zonedScheduleCalls, hasLength(1));

      final args = zonedScheduleCalls.first.arguments as Map<dynamic, dynamic>;
      final platformSpecifics =
          args['platformSpecifics'] as Map<dynamic, dynamic>;

      expect(args['id'], _stableHash('task-123'));
      expect(args['title'], 'Task Reminder');
      expect(args['body'], 'Buy milk');
      expect(args['payload'], 'task_${_stableHash('task-123')}');
      expect(platformSpecifics['channelId'], 'task_reminders');
      expect(platformSpecifics['scheduleMode'], 'exactAllowWhileIdle');
      expect(args['scheduledDateTimeISO8601'], isNotNull);
    });

    test('cancels the reminder when reminderTime is null', () async {
      final service = ReminderService();
      final task = TaskModel(
        id: 'task-456',
        title: 'No reminder',
        createdAt: DateTime(2024, 6, 15),
        updatedAt: DateTime(2024, 6, 15),
      );

      await service.scheduleTaskReminder(task);

      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);

      final cancelCalls = calls.where((c) => c.method == 'cancel').toList();
      expect(cancelCalls, hasLength(1));
      expect(
        _cancelId(cancelCalls.first.arguments),
        _stableHash('task-456'),
      );
    });

    test('cancels the reminder when the task is completed', () async {
      final service = ReminderService();
      final task = TaskModel(
        id: 'task-789',
        title: 'Done already',
        createdAt: DateTime(2024, 6, 15),
        updatedAt: DateTime(2024, 6, 15),
        reminderTime: DateTime.now().add(const Duration(hours: 1)),
        isCompleted: true,
      );

      await service.scheduleTaskReminder(task);

      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);

      final cancelCalls = calls.where((c) => c.method == 'cancel').toList();
      expect(cancelCalls, hasLength(1));
      expect(
        _cancelId(cancelCalls.first.arguments),
        _stableHash('task-789'),
      );
    });
  });

  group('ReminderService.cancelTaskReminder', () {
    test('cancels the notification derived from the task id', () async {
      final service = ReminderService();

      await service.cancelTaskReminder('task-abc');

      final cancelCalls = calls.where((c) => c.method == 'cancel').toList();
      expect(cancelCalls, hasLength(1));
      expect(
        _cancelId(cancelCalls.first.arguments),
        _stableHash('task-abc'),
      );
    });
  });
}

int _stableHash(String taskId) {
  int hash = 0;
  for (int i = 0; i < taskId.length; i++) {
    hash = (31 * hash + taskId.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash;
}

int _cancelId(dynamic arguments) {
  if (arguments is int) return arguments;
  if (arguments is Map) return arguments['id'] as int;
  throw ArgumentError('Unexpected cancel arguments: $arguments');
}
