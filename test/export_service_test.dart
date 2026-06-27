import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:daily_tracker/core/services/export_service.dart';
import 'package:daily_tracker/data/local/database_helper.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/data/models/daily_completion_model.dart';
import 'package:daily_tracker/data/models/task_log_model.dart';

TaskModel _makeTask({
  String id = 'task-1',
  String title = 'No Sugar',
  bool completed = false,
  String? category,
  String taskType = 'checklist',
}) {
  final now = DateTime.now();
  return TaskModel(
    id: id,
    title: title,
    createdAt: now,
    updatedAt: now,
    isCompleted: completed,
    category: category,
    taskType: taskType,
  );
}

TaskLogModel _makeLog({
  String id = 'log-1',
  String taskId = 'task-1',
  String date = '2026-05-31',
  String? comment,
  String? mediaPath,
}) {
  final now = DateTime.now();
  return TaskLogModel(
    id: id,
    taskId: taskId,
    date: date,
    isCompleted: true,
    comment: comment,
    mediaPath: mediaPath,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ExportService — round-trip serialization', () {
    late DatabaseHelper dbHelper;
    late ExportService exportService;
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
      exportService = ExportService(dbHelper);
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

    test('exports and re-imports tasks, completions, logs', () async {
      await dbHelper.insertTask(_makeTask());
      await dbHelper.upsertDailyCompletion(DailyCompletionModel(
        id: 'comp-1',
        date: DateTime.now(),
        totalTasks: 5,
        completedTasks: 3,
        completionRate: 0.6,
      ));
      await dbHelper.insertTaskLog(
        _makeLog(comment: 'Felt great', mediaPath: '/img.jpg'),
      );

      final json = await exportService.exportToJson();
      expect(json, contains('task-1'));
      expect(json, contains('No Sugar'));
      expect(json, contains('Felt great'));
      expect(json, contains('/img.jpg'));

      await dbHelper.wipeAllData();

      final ok = await exportService.importFromJson(json);
      expect(ok, isTrue);

      final tasks = await dbHelper.getAllActiveTasks();
      final completions = await dbHelper.getDailyCompletionsRange(
        DateTime.now().subtract(const Duration(days: 365)),
        DateTime.now(),
      );
      final logs = await dbHelper.getAllTaskLogs();

      expect(tasks, hasLength(1));
      expect(tasks.first.title, 'No Sugar');
      expect(completions.first.completedTasks, 3);
      expect(logs.first.comment, 'Felt great');
      expect(logs.first.mediaPath, '/img.jpg');
    });

    test('exports empty DB to valid JSON with empty arrays', () async {
      final json = await exportService.exportToJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['tasks'], isEmpty);
      expect(decoded['completions'], isEmpty);
      expect(decoded['taskLogs'], isEmpty);
      expect(decoded['version'], equals(2));
    });

    test('import preserves all optional nullable fields', () async {
      await dbHelper
          .insertTask(_makeTask(category: 'Health', taskType: 'numeric'));
      await dbHelper.insertTaskLog(_makeLog(comment: null, mediaPath: null));

      final json = await exportService.exportToJson();
      await dbHelper.wipeAllData();

      await exportService.importFromJson(json);

      final tasks = await dbHelper.getAllActiveTasks();
      final logs = await dbHelper.getAllTaskLogs();

      expect(tasks.first.category, 'Health');
      expect(tasks.first.taskType, 'numeric');
      expect(logs.first.comment, isNull);
      expect(logs.first.mediaPath, isNull);
    });

    test('import replaces existing data atomically (old data cleared)',
        () async {
      await dbHelper.insertTask(_makeTask(id: 'old-task', title: 'Old'));
      final newJson = jsonEncode({
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': [_makeTask(id: 'new-task', title: 'New').toMap()],
        'completions': [],
        'taskLogs': [],
      });

      await exportService.importFromJson(newJson);

      final tasks = await dbHelper.getAllActiveTasks();
      expect(tasks, hasLength(1));
      expect(tasks.first.id, 'new-task');
      expect(tasks.first.title, 'New');
    });

    test('import rejects unsupported version number', () async {
      final badJson = jsonEncode({
        'version': 99,
        'tasks': [],
        'completions': [],
        'taskLogs': [],
      });
      expect(
        () => exportService.importFromJson(badJson),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('import rejects malformed JSON', () async {
      expect(
        () => exportService.importFromJson('not json at all'),
        throwsA(anything),
      );
    });

    test('import rejects task with empty id', () async {
      final json = jsonEncode({
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': [
          {
            'id': '',
            'title': 'No ID',
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
            'isCompleted': 0,
            'isRecurring': 0,
            'priority': 0,
            'isDeleted': 0,
            'version': 1,
            'syncStatus': 'pending',
          }
        ],
        'completions': [],
        'taskLogs': [],
      });
      expect(
        () => exportService.importFromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('import rejects duplicate task ids in the same batch', () async {
      final taskMap = _makeTask(id: 'dup').toMap();
      final json = jsonEncode({
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': [taskMap, taskMap],
        'completions': [],
        'taskLogs': [],
      });
      expect(
        () => exportService.importFromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('import rejects task log with empty taskId', () async {
      final json = jsonEncode({
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': [],
        'completions': [],
        'taskLogs': [
          {
            'id': 'log-x',
            'taskId': '',
            'date': '2026-06-01',
            'isCompleted': 0,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
            'syncStatus': 'pending',
          }
        ],
      });
      expect(
        () => exportService.importFromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('exportToCsv produces header row and one data row per completion',
        () async {
      await dbHelper.upsertDailyCompletion(DailyCompletionModel(
        id: '2026-01-01T00:00:00.000',
        date: DateTime(2026, 1, 1),
        totalTasks: 10,
        completedTasks: 7,
        completionRate: 0.7,
      ));
      final csv = await exportService.exportToCsv();
      expect(
          csv, contains('Date,Total Tasks,Completed Tasks,Completion Rate %'));
      expect(csv, contains('2026-01-01'));
      expect(csv, contains('10'));
      expect(csv, contains('70.0'));
    });

    test('version 1 backup is accepted (backward compat)', () async {
      final json = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': [_makeTask().toMap()],
        'completions': [],
        'taskLogs': [],
      });
      final ok = await exportService.importFromJson(json);
      expect(ok, isTrue);

      final tasks = await dbHelper.getAllActiveTasks();
      expect(tasks, hasLength(1));
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
