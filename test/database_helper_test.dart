import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:daily_tracker/data/local/database_helper.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/data/models/task_log_model.dart';
import 'package:daily_tracker/data/models/daily_completion_model.dart';
import 'package:daily_tracker/core/extensions/date_extensions.dart';

void main() {

  late DatabaseHelper dbHelper;

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

  group('DatabaseHelper CRUD', () {
    test('insertTask and getTask roundtrip', () async {
      final task = TaskModel(
        id: 'task-1',
        title: 'Test Task',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await dbHelper.insertTask(task);
      final retrieved = await dbHelper.getTask('task-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('task-1'));
      expect(retrieved.title, equals('Test Task'));
      expect(retrieved.isDeleted, isFalse);
    });

    test('insertTask throws when primary key is empty', () async {
      final task = TaskModel(
        id: '',
        title: 'No ID',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(() => dbHelper.insertTask(task), throwsA(isA<ArgumentError>()));
    });

    test('deleteTask soft-deletes and removes logs', () async {
      final task = TaskModel(
        id: 'task-delete',
        title: 'Delete Me',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task);

      final log = TaskLogModel(
        id: 'log-delete',
        taskId: 'task-delete',
        date: '2024-06-15',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTaskLog(log);

      await dbHelper.deleteTask('task-delete');

      final retrieved = await dbHelper.getTask('task-delete');
      expect(retrieved, isNull);

      final logs = await dbHelper.getTaskLogsForTask('task-delete');
      expect(logs, isEmpty);
    });

    test('updateTaskCompletion creates daily completion stats', () async {
      final task = TaskModel(
        id: 'task-toggle',
        title: 'Toggle Me',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task);

      final now = DateTime.now();
      await dbHelper.updateTaskCompletion(
        task.copyWith(
          isCompleted: true,
          completedAt: now,
          updatedAt: now,
          syncStatus: 'pending',
        ),
      );

      final today = DateTime.now();
      final completion = await dbHelper.getDailyCompletion(today);
      expect(completion, isNotNull);
      expect(completion!.totalTasks, equals(1));
      expect(completion.completedTasks, equals(1));
      expect(completion.completionRate, equals(1.0));

      final log = await dbHelper.getTaskLog('task-toggle', _todayString());
      expect(log, isNotNull);
      expect(log!.isCompleted, isTrue);
    });

    test('updateTaskCompletion updates existing log', () async {
      final task = TaskModel(
        id: 'task-toggle-2',
        title: 'Toggle Me Twice',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task);

      var now = DateTime.now();
      await dbHelper.updateTaskCompletion(
        task.copyWith(
          isCompleted: true,
          completedAt: now,
          updatedAt: now,
          syncStatus: 'pending',
        ),
      );

      now = DateTime.now();
      await dbHelper.updateTaskCompletion(
        task.copyWith(
          isCompleted: false,
          completedAt: null,
          updatedAt: now,
          syncStatus: 'pending',
        ),
      );

      final log = await dbHelper.getTaskLog('task-toggle-2', _todayString());
      expect(log, isNotNull);
      expect(log!.isCompleted, isFalse);
      expect(log.completedAt, isNull);
    });

    test('getTasksForDate returns all active non-deleted tasks', () async {
      final task1 = TaskModel(
        id: 'task-active',
        title: 'Active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final task2 = TaskModel(
        id: 'task-deleted',
        title: 'Deleted',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task1);
      await dbHelper.insertTask(task2);
      await dbHelper.deleteTask('task-deleted');

      final tasks = await dbHelper.getTasksForDate(DateTime.now());
      expect(tasks, hasLength(1));
      expect(tasks.first.id, equals('task-active'));
    });

    test('getTaskLogsForDate filters by date', () async {
      final log1 = TaskLogModel(
        id: 'log-1',
        taskId: 'task-1',
        date: '2024-06-15',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final log2 = TaskLogModel(
        id: 'log-2',
        taskId: 'task-1',
        date: '2024-06-16',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTaskLog(log1);
      await dbHelper.insertTaskLog(log2);

      final logs = await dbHelper.getTaskLogsForDate('2024-06-15');
      expect(logs, hasLength(1));
      expect(logs.first.date, equals('2024-06-15'));
    });

    test('importBatch atomically replaces all data', () async {
      final oldTask = TaskModel(
        id: 'old-task',
        title: 'Old',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(oldTask);

      final newTask = TaskModel(
        id: 'new-task',
        title: 'New',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final completion = DailyCompletionModel(
        id: '2024-06-15',
        date: DateTime(2024, 6, 15),
        totalTasks: 1,
        completedTasks: 1,
        completionRate: 1.0,
      );
      final log = TaskLogModel(
        id: 'new-log',
        taskId: 'new-task',
        date: '2024-06-15',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await dbHelper.importBatch(
        tasks: [newTask],
        completions: [completion],
        logs: [log],
      );

      final tasks = await dbHelper.getAllActiveTasks();
      expect(tasks, hasLength(1));
      expect(tasks.first.id, equals('new-task'));

      final completions = await dbHelper.getDailyCompletionsRange(
        DateTime(2024, 6, 15),
        DateTime(2024, 6, 15),
      );
      expect(completions, hasLength(1));

      final logs = await dbHelper.getAllTaskLogs();
      expect(logs, hasLength(1));
    });

    test('wipeAllData removes everything', () async {
      final task = TaskModel(
        id: 'task-wipe',
        title: 'Wipe',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task);
      await dbHelper.wipeAllData();

      final tasks = await dbHelper.getAllActiveTasks();
      expect(tasks, isEmpty);
    });
  });

  group('DatabaseHelper analytics', () {
    test('getStreakCount returns zero with no data', () async {
      final streak = await dbHelper.getStreakCount();
      expect(streak, equals(0));
    });

    test('getCategoryStats aggregates correctly', () async {
      final task1 = TaskModel(
        id: 'cat-1',
        title: 'Do Task',
        category: 'Do',
        isCompleted: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        completedAt: DateTime.now(),
      );
      final task2 = TaskModel(
        id: 'cat-2',
        title: 'Health Task',
        category: 'Health',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task1);
      await dbHelper.insertTask(task2);

      final stats = await dbHelper.getCategoryStats();
      final doStat = stats.firstWhere((s) => s.category == 'Do');
      final healthStat = stats.firstWhere((s) => s.category == 'Health');

      expect(doStat.total, equals(1));
      expect(doStat.completed, equals(1));
      expect(healthStat.total, equals(1));
      expect(healthStat.completed, equals(0));
    });

    group('streak edge cases', () {
      test('getStreakCount is zero when no completions meet threshold', () async {
        final today = DateTime.now().dateOnly;
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(
            id: _dateString(today),
            date: today,
            totalTasks: 2,
            completedTasks: 0,
            completionRate: 0.0,
          ),
        );

        expect(await dbHelper.getStreakCount(), equals(0));
      });

      test('getStreakCount breaks when a day is missed', () async {
        final today = DateTime.now().dateOnly;
        final yesterday = today.subtract(const Duration(days: 1));
        final threeDaysAgo = today.subtract(const Duration(days: 3));

        // Yesterday is complete, but the day before yesterday is missing.
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(
            id: _dateString(yesterday),
            date: yesterday,
            totalTasks: 1,
            completedTasks: 1,
            completionRate: 1.0,
          ),
        );
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(
            id: _dateString(threeDaysAgo),
            date: threeDaysAgo,
            totalTasks: 1,
            completedTasks: 1,
            completionRate: 1.0,
          ),
        );

        expect(await dbHelper.getStreakCount(), equals(1));
      });

      test('getStreakCount counts today when threshold is exactly 0.5', () async {
        final today = DateTime.now().dateOnly;
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(
            id: _dateString(today),
            date: today,
            totalTasks: 2,
            completedTasks: 1,
            completionRate: 0.5,
          ),
        );

        expect(await dbHelper.getStreakCount(), equals(1));
      });

      test('getStreakCount counts consecutive days ending yesterday', () async {
        final today = DateTime.now().dateOnly;
        final yesterday = today.subtract(const Duration(days: 1));
        final twoDaysAgo = today.subtract(const Duration(days: 2));

        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(
            id: _dateString(yesterday),
            date: yesterday,
            totalTasks: 1,
            completedTasks: 1,
            completionRate: 1.0,
          ),
        );
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(
            id: _dateString(twoDaysAgo),
            date: twoDaysAgo,
            totalTasks: 1,
            completedTasks: 1,
            completionRate: 1.0,
          ),
        );

        expect(await dbHelper.getStreakCount(), equals(2));
      });

      test('getBestStreakCount finds longest run with gaps', () async {
        final base = DateTime(2024, 6, 10);
        final completions = [
          // 3-day run
          DailyCompletionModel(id: '2024-06-01', date: base.subtract(const Duration(days: 9)), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
          DailyCompletionModel(id: '2024-06-02', date: base.subtract(const Duration(days: 8)), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
          DailyCompletionModel(id: '2024-06-03', date: base.subtract(const Duration(days: 7)), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
          // Gap + 2-day run
          DailyCompletionModel(id: '2024-06-05', date: base.subtract(const Duration(days: 5)), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
          DailyCompletionModel(id: '2024-06-06', date: base.subtract(const Duration(days: 4)), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
          // Low completion day breaks the streak
          DailyCompletionModel(id: '2024-06-07', date: base.subtract(const Duration(days: 3)), totalTasks: 1, completedTasks: 0, completionRate: 0.0),
          // Single day after break
          DailyCompletionModel(id: '2024-06-09', date: base.subtract(const Duration(days: 1)), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
        ];

        for (final completion in completions) {
          await dbHelper.upsertDailyCompletion(completion);
        }

        expect(await dbHelper.getBestStreakCount(), equals(3));
      });

      test('getBestStreakCount ignores below-threshold days', () async {
        final base = DateTime(2024, 6, 15);
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: '2024-06-15', date: base, totalTasks: 2, completedTasks: 1, completionRate: 0.5),
        );
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: '2024-06-16', date: base.add(const Duration(days: 1)), totalTasks: 2, completedTasks: 0, completionRate: 0.49),
        );
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: '2024-06-17', date: base.add(const Duration(days: 2)), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
        );

        expect(await dbHelper.getBestStreakCount(), equals(1));
      });

      test('getAverageCompletionRate returns arithmetic mean of mixed rates', () async {
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: '2024-06-01', date: DateTime(2024, 6, 1), totalTasks: 1, completedTasks: 0, completionRate: 0.0),
        );
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: '2024-06-02', date: DateTime(2024, 6, 2), totalTasks: 2, completedTasks: 1, completionRate: 0.5),
        );
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: '2024-06-03', date: DateTime(2024, 6, 3), totalTasks: 1, completedTasks: 1, completionRate: 1.0),
        );

        expect(await dbHelper.getAverageCompletionRate(), closeTo(0.5, 0.001));
      });

      test('getAverageCompletionRate returns zero with no data', () async {
        expect(await dbHelper.getAverageCompletionRate(), equals(0.0));
      });

      test('getStreakCount tolerates duplicate and out-of-order completion rows', () async {
        final today = DateTime.now().dateOnly;
        final yesterday = today.subtract(const Duration(days: 1));

        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: _dateString(yesterday), date: yesterday, totalTasks: 1, completedTasks: 1, completionRate: 1.0),
        );
        // Duplicate/upsert for same day should not inflate streak.
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: _dateString(yesterday), date: yesterday, totalTasks: 1, completedTasks: 1, completionRate: 1.0),
        );
        await dbHelper.upsertDailyCompletion(
          DailyCompletionModel(id: _dateString(today), date: today, totalTasks: 1, completedTasks: 1, completionRate: 1.0),
        );

        expect(await dbHelper.getStreakCount(), equals(2));
      });
    });
  });
}

String _dateString(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _todayString() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
