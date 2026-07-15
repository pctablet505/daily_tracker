import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:daily_tracker/core/extensions/date_extensions.dart';
import 'package:daily_tracker/data/local/database_helper.dart';
import 'package:daily_tracker/data/repositories/task_repository.dart';
import 'package:daily_tracker/domain/entities/recurrence_rule.dart';

void main() {
  late DatabaseHelper dbHelper;
  late TaskRepository repository;
  late Directory tempDir;

  setUpAll(() async {
    _ensureSqlite3Loaded();
    databaseFactory = createDatabaseFactoryFfi(
      ffiInit: _ensureSqlite3Loaded,
    );
    tempDir = await Directory.systemTemp.createTemp('daily_tracker_test_');
  });

  setUp(() async {
    final dbFile = File(p.join(tempDir.path, 'daily_tracker.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    DatabaseHelper.resetTestDatabasePath();
    DatabaseHelper.setTestDatabasePath(dbFile.path);
    dbHelper = DatabaseHelper();
    repository = TaskRepository(dbHelper);
  });

  tearDown(() async {
    try {
      await dbHelper.close();
    } catch (_) {}
    DatabaseHelper.resetTestDatabasePath();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('resetRecurringTasksForNewDay', () {
    test('weekly Mon/Wed/Fri task resets only on occurring weekdays', () async {
      final today = DateTime.now().dateOnly;
      final todayWeekday = today.weekday;
      // Ensure the set contains today plus two other distinct weekdays.
      final days = {
        todayWeekday,
        (todayWeekday % 7) + 1,
        ((todayWeekday + 1) % 7) + 1,
      };
      final rule = RecurrenceRule.weekly(days);

      final task = await repository.createTask(
        title: 'Weekly Task',
        isRecurring: true,
        recurrenceRule: rule.encode(),
      );

      await dbHelper.updateTaskCompletion(
        task.copyWith(
          isCompleted: true,
          completedAt: today.subtract(const Duration(days: 1)),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        ),
      );

      await repository.resetRecurringTasksForNewDay();

      final after = await repository.getTask(task.id);
      expect(after, isNotNull);
      expect(after!.isCompleted, isFalse);
      expect(after.completedAt, isNull);
    });

    test('weekly task does not reset on a non-occurring weekday', () async {
      final today = DateTime.now().dateOnly;
      final tomorrowWeekday = (today.weekday % 7) + 1;
      final rule = RecurrenceRule.weekly({tomorrowWeekday});

      final task = await repository.createTask(
        title: 'Off-day Task',
        isRecurring: true,
        recurrenceRule: rule.encode(),
      );

      await dbHelper.updateTaskCompletion(
        task.copyWith(
          isCompleted: true,
          completedAt: today.subtract(const Duration(days: 1)),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        ),
      );

      await repository.resetRecurringTasksForNewDay();

      final after = await repository.getTask(task.id);
      expect(after, isNotNull);
      expect(after!.isCompleted, isTrue);
    });

    test('everyNDays=2 resets on the correct days relative to createdAt',
        () async {
      final today = DateTime.now().dateOnly;
      final rule = RecurrenceRule.everyNDays(2);

      final task = await repository.createTask(
        title: 'Every Other Day Task',
        isRecurring: true,
        recurrenceRule: rule.encode(),
      );

      await dbHelper.updateTaskCompletion(
        task.copyWith(
          isCompleted: true,
          completedAt: today.subtract(const Duration(days: 1)),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        ),
      );

      await repository.resetRecurringTasksForNewDay();

      final after = await repository.getTask(task.id);
      expect(after, isNotNull);
      expect(after!.isCompleted, isFalse);
      expect(after.completedAt, isNull);
    });

    test('legacy daily row still behaves as daily end-to-end', () async {
      final db = await dbHelper.database;
      final today = DateTime.now().dateOnly;
      final createdAtStr = today.toIso8601String();
      const id = 'legacy-daily-task';

      await db.rawInsert('''
        INSERT INTO tasks (
          id, title, createdAt, updatedAt, isCompleted, isRecurring,
          recurrenceRule, priority, isDeleted, version, syncStatus
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        id,
        'Legacy Daily',
        createdAtStr,
        createdAtStr,
        1,
        1,
        'daily',
        0,
        0,
        1,
        'pending',
      ]);

      final task = await repository.getTask(id);
      expect(task, isNotNull);
      expect(task!.recurrenceRuleModel, const RecurrenceRule.daily());

      await dbHelper.updateTaskCompletion(
        task.copyWith(
          isCompleted: true,
          completedAt: today.subtract(const Duration(days: 1)),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        ),
      );

      await repository.resetRecurringTasksForNewDay();

      final after = await repository.getTask(id);
      expect(after, isNotNull);
      expect(after!.isCompleted, isFalse);
      expect(after.completedAt, isNull);
    });
  });

  group('getTasksForDate filtering', () {
    test('weekly task is absent on non-occurring date and present on occurring one',
        () async {
      final today = DateTime.now().dateOnly;
      final tomorrow = today.add(const Duration(days: 1));
      final rule = RecurrenceRule.weekly({today.weekday});

      await repository.createTask(
        title: 'Weekly Filter',
        isRecurring: true,
        recurrenceRule: rule.encode(),
      );

      final occurring = await repository.getTasksForDate(today);
      expect(occurring, hasLength(1));

      final nonOccurring = await repository.getTasksForDate(tomorrow);
      expect(nonOccurring, isEmpty);
    });

    test('non-recurring task appears on both occurring and non-occurring dates',
        () async {
      final today = DateTime.now().dateOnly;
      final tomorrow = today.add(const Duration(days: 1));

      await repository.createTask(title: 'One-off Task');

      final todayTasks = await repository.getTasksForDate(today);
      final tomorrowTasks = await repository.getTasksForDate(tomorrow);

      expect(todayTasks, hasLength(1));
      expect(tomorrowTasks, hasLength(1));
    });
  });
}

/// Locates a prebuilt libsqlite3 shared object on the host and wires it into
/// the sqlite3 package. This allows unit tests to run on Linux hosts that do
/// not have a system libsqlite3.so in the default library search path.
void _ensureSqlite3Loaded() {
  const candidates = [
    '/home/pctablet505/.cache/bazel/_bazel_pctablet505/c9d4eae62017b0ae004e50f66ccf4980/external/sysroot_linux_x86_64_glibc_2_27/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/lib/x86_64-linux-gnu/libsqlite3.so.0',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      sqlite3_open.open.overrideFor(
        sqlite3_open.OperatingSystem.linux,
        () => DynamicLibrary.open(path),
      );
      return;
    }
  }

  throw StateError(
    'Could not find libsqlite3.so.0. Please install libsqlite3-dev or provide a valid path.',
  );
}
