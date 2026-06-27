import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:daily_tracker/core/extensions/date_extensions.dart';
import 'package:daily_tracker/data/local/database_helper.dart';
import 'package:daily_tracker/data/models/task_log_model.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/data/repositories/task_repository.dart';

void main() {
  late DatabaseHelper dbHelper;
  late TaskRepository repository;
  late Directory tempDir;

  setUpAll(() async {
    _ensureSqlite3Loaded();
    databaseFactory = createDatabaseFactoryFfi(
      ffiInit: _ensureSqlite3Loaded,
    );
    tempDir = await Directory.systemTemp.createTemp('daily_tracker_repo_test_');
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

  group('rapid toggleTaskCompletion', () {
    test('final state matches parity after many consecutive toggles', () async {
      var task = await repository.createTask(title: 'Rapid Toggle');
      expect(task.isCompleted, isFalse);

      // Toggle an odd number of times; final state should be completed.
      for (var i = 0; i < 5; i++) {
        await repository.toggleTaskCompletion(task);
        task = (await repository.getTask(task.id))!;
      }
      expect(task.isCompleted, isTrue);

      // Toggle the same odd number of additional times; final state should be incomplete.
      for (var i = 0; i < 5; i++) {
        await repository.toggleTaskCompletion(task);
        task = (await repository.getTask(task.id))!;
      }
      expect(task.isCompleted, isFalse);
    });

    test('does not create duplicate task logs for the same day', () async {
      var task = await repository.createTask(title: 'Log Uniqueness');
      final dateStr = _todayString();

      for (var i = 0; i < 20; i++) {
        await repository.toggleTaskCompletion(task);
        task = (await repository.getTask(task.id))!;
      }

      final logs = await dbHelper.getTaskLogsForDate(dateStr);
      expect(logs, hasLength(1));
      expect(logs.first.taskId, equals(task.id));
      expect(logs.first.date, equals(dateStr));
    });

    test('handles a large number of tasks without data loss', () async {
      const count = 100;
      final tasks = <TaskModel>[];

      for (var i = 0; i < count; i++) {
        final task = await repository.createTask(title: 'Bulk Task $i');
        tasks.add(task);
      }

      for (final task in tasks) {
        final now = DateTime.now();
        await dbHelper.updateTaskCompletion(
          task.copyWith(
            isCompleted: true,
            completedAt: now,
            updatedAt: now,
            syncStatus: 'pending',
          ),
        );
      }

      final completion = await dbHelper.getDailyCompletion(DateTime.now());
      expect(completion, isNotNull);
      expect(completion!.totalTasks, equals(count));
      expect(completion.completedTasks, equals(count));
      expect(completion.completionRate, equals(1.0));
    });
  });

  group('resetRecurringTasksForNewDay', () {
    test('only resets recurring tasks completed yesterday, not today', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      final yesterdayTask = await repository.createTask(
        title: 'Recurring Yesterday',
        isRecurring: true,
      );
      final todayTask = await repository.createTask(
        title: 'Recurring Today',
        isRecurring: true,
      );
      final nonRecurringTask = await repository.createTask(
        title: 'Non-Recurring Yesterday',
        isRecurring: false,
      );

      // Simulate completion timestamps directly in the database.
      await dbHelper.updateTask(
        yesterdayTask.copyWith(
          isCompleted: true,
          completedAt: yesterday,
          updatedAt: DateTime.now(),
        ),
      );
      await dbHelper.updateTask(
        todayTask.copyWith(
          isCompleted: true,
          completedAt: today,
          updatedAt: DateTime.now(),
        ),
      );
      await dbHelper.updateTask(
        nonRecurringTask.copyWith(
          isCompleted: true,
          completedAt: yesterday,
          updatedAt: DateTime.now(),
        ),
      );

      await repository.resetRecurringTasksForNewDay();

      final refreshedYesterday = (await repository.getTask(yesterdayTask.id))!;
      final refreshedToday = (await repository.getTask(todayTask.id))!;
      final refreshedNonRecurring = (await repository.getTask(nonRecurringTask.id))!;

      expect(refreshedYesterday.isCompleted, isFalse);
      expect(refreshedYesterday.completedAt, isNull);

      expect(refreshedToday.isCompleted, isTrue);
      expect(refreshedToday.completedAt, isNotNull);
      expect(refreshedToday.completedAt!.dateOnly, equals(today.dateOnly));

      expect(refreshedNonRecurring.isCompleted, isTrue);
      expect(refreshedNonRecurring.completedAt, isNotNull);
    });

    test('leaves incomplete recurring tasks unchanged', () async {
      final task = await repository.createTask(
        title: 'Recurring Incomplete',
        isRecurring: true,
      );
      expect(task.isCompleted, isFalse);

      await repository.resetRecurringTasksForNewDay();

      final refreshed = (await repository.getTask(task.id))!;
      expect(refreshed.isCompleted, isFalse);
      expect(refreshed.completedAt, isNull);
    });

    test('leaves non-recurring completed tasks unchanged', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final task = await repository.createTask(
        title: 'Non-Recurring Completed',
        isRecurring: false,
      );
      await dbHelper.updateTask(
        task.copyWith(
          isCompleted: true,
          completedAt: yesterday,
          updatedAt: DateTime.now(),
        ),
      );

      await repository.resetRecurringTasksForNewDay();

      final refreshed = (await repository.getTask(task.id))!;
      expect(refreshed.isCompleted, isTrue);
      expect(refreshed.completedAt, isNotNull);
    });
  });

  group('saveTaskLog upsert', () {
    test('creates then updates the same log entry', () async {
      final task = await repository.createTask(title: 'Log Upsert');
      final date = DateTime.now().dateOnly;
      final dateStr = _dateString(date);

      await repository.saveTaskLog(
        TaskLogModel(
          id: 'first-log-id',
          taskId: task.id,
          date: dateStr,
          isCompleted: false,
          comment: 'initial',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await repository.saveTaskLog(
        TaskLogModel(
          id: 'second-log-id',
          taskId: task.id,
          date: dateStr,
          isCompleted: true,
          comment: 'updated',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final logs = await repository.getTaskLogsForTask(task.id);
      expect(logs, hasLength(1));

      final saved = logs.first;
      expect(saved.isCompleted, isTrue);
      expect(saved.comment, equals('updated'));
      // The repository must reuse the existing id rather than the second id.
      expect(saved.id, equals('first-log-id'));
    });

    test('remains consistent under rapid repeated saves', () async {
      final task = await repository.createTask(title: 'Rapid Log Upsert');
      final date = DateTime.now().dateOnly;
      final dateStr = _dateString(date);

      const iterations = 50;
      for (var i = 0; i < iterations; i++) {
        await repository.saveTaskLog(
          TaskLogModel(
            id: 'log-$i',
            taskId: task.id,
            date: dateStr,
            isCompleted: i % 2 == 0,
            comment: 'version $i',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      final allLogs = await dbHelper.getAllTaskLogs();
      final taskLogs = allLogs.where((l) => l.taskId == task.id).toList();
      expect(taskLogs, hasLength(1));

      final saved = taskLogs.first;
      expect(saved.isCompleted, isFalse); // iterations is even, last i=49 -> odd -> false
      expect(saved.comment, equals('version ${iterations - 1}'));
    });

    test('creates separate logs for different dates', () async {
      final task = await repository.createTask(title: 'Multi-Date Logs');
      final today = DateTime.now().dateOnly;
      final yesterday = today.subtract(const Duration(days: 1));

      await repository.saveTaskLog(
        TaskLogModel(
          id: 'today-log',
          taskId: task.id,
          date: _dateString(today),
          isCompleted: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await repository.saveTaskLog(
        TaskLogModel(
          id: 'yesterday-log',
          taskId: task.id,
          date: _dateString(yesterday),
          isCompleted: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final logs = await repository.getTaskLogsForTask(task.id);
      expect(logs, hasLength(2));
    });
  });
}

String _todayString() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _dateString(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
