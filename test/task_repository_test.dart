import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:daily_tracker/data/local/database_helper.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/data/repositories/task_repository.dart';

void main() {
  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late TaskRepository repository;

  setUpAll(() async {
    _ensureSqlite3Loaded();
    databaseFactory = createDatabaseFactoryFfi(ffiInit: _ensureSqlite3Loaded);
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

  group('TaskRepository.createTask', () {
    test('creates a checklist task by default', () async {
      final task = await repository.createTask(title: 'Drink water');

      expect(task.title, equals('Drink water'));
      expect(task.taskType, equals('checklist'));
      expect(task.isCompleted, isFalse);
      expect(task.isDeleted, isFalse);

      final retrieved = await repository.getTask(task.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.title, equals('Drink water'));
    });

    test('creates a numeric task with category', () async {
      final task = await repository.createTask(
        title: 'Weight',
        description: 'kg',
        taskType: 'numeric',
        category: 'Health',
        priority: 2,
      );

      expect(task.taskType, equals('numeric'));
      expect(task.category, equals('Health'));
      expect(task.priority, equals(2));
      expect(task.description, equals('kg'));
    });

    test('throws for empty title', () async {
      await expectLater(
        repository.createTask(title: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TaskRepository.updateTask', () {
    test('updates task fields', () async {
      final task = await repository.createTask(title: 'Old Title');
      final updated = await repository.updateTask(
        task,
        title: 'New Title',
        category: 'Work',
        priority: 1,
      );

      expect(updated.title, equals('New Title'));
      expect(updated.category, equals('Work'));
      expect(updated.priority, equals(1));

      final retrieved = await repository.getTask(task.id);
      expect(retrieved!.title, equals('New Title'));
    });

    test('can clear nullable fields', () async {
      final task = await repository.createTask(
        title: 'With Category',
        category: 'Personal',
      );
      final updated = await repository.updateTask(
        task,
        category: null,
      );

      expect(updated.category, isNull);
    });
  });

  group('TaskRepository.toggleTaskCompletion', () {
    test('toggles completion and back', () async {
      final task = await repository.createTask(title: 'Toggle');
      await repository.toggleTaskCompletion(task);

      var tasks = await repository.getAllActiveTasks();
      expect(tasks.first.isCompleted, isTrue);

      await repository.toggleTaskCompletion(tasks.first);
      tasks = await repository.getAllActiveTasks();
      expect(tasks.first.isCompleted, isFalse);
    });
  });

  group('TaskRepository.deleteTask', () {
    test('soft-deletes task', () async {
      final task = await repository.createTask(title: 'Delete');
      await repository.deleteTask(task.id);

      final retrieved = await repository.getTask(task.id);
      expect(retrieved, isNull);

      final all = await repository.getAllActiveTasks();
      expect(all, isEmpty);
    });
  });

  group('TaskRepository.resetRecurringTasksForNewDay', () {
    test('resets recurring task completed yesterday', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final task = TaskModel(
        id: 'recurring-task',
        title: 'Daily Recurring',
        isRecurring: true,
        isCompleted: true,
        completedAt: yesterday,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task);

      await repository.resetRecurringTasksForNewDay();

      final retrieved = await repository.getTask('recurring-task');
      expect(retrieved!.isCompleted, isFalse);
      expect(retrieved.completedAt, isNull);
    });

    test('does not reset recurring task completed today', () async {
      final now = DateTime.now();
      final task = TaskModel(
        id: 'recurring-today',
        title: 'Daily Recurring',
        isRecurring: true,
        isCompleted: true,
        completedAt: now,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbHelper.insertTask(task);

      await repository.resetRecurringTasksForNewDay();

      final retrieved = await repository.getTask('recurring-today');
      expect(retrieved!.isCompleted, isTrue);
    });
  });
}

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
