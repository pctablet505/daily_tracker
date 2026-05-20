import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/task_model.dart';
import '../models/daily_completion_model.dart';
import '../models/sync_queue_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'daily_tracker.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        reminderTime TEXT,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        isRecurring INTEGER NOT NULL DEFAULT 0,
        recurrenceRule TEXT,
        category TEXT,
        priority INTEGER NOT NULL DEFAULT 0,
        completedAt TEXT,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        syncStatus TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_completions (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        totalTasks INTEGER NOT NULL DEFAULT 0,
        completedTasks INTEGER NOT NULL DEFAULT 0,
        completionRate REAL NOT NULL DEFAULT 0.0,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        entityType TEXT NOT NULL,
        entityId TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        retryCount INTEGER NOT NULL DEFAULT 0,
        isProcessed INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX idx_tasks_date ON tasks(createdAt)');
    await db.execute('CREATE INDEX idx_tasks_completed ON tasks(isCompleted)');
    await db.execute('CREATE INDEX idx_tasks_deleted ON tasks(isDeleted)');
    await db.execute('CREATE INDEX idx_sync_queue_processed ON sync_queue(isProcessed)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here
  }

  // ==================== TASKS ====================

  Future<String> insertTask(TaskModel task) async {
    final db = await database;
    await db.insert('tasks', task.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return task.id;
  }

  Future<int> updateTask(TaskModel task) async {
    final db = await database;
    return await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<int> deleteTask(String id) async {
    final db = await database;
    return await db.update(
      'tasks',
      {'isDeleted': 1, 'updatedAt': DateTime.now().toIso8601String(), 'syncStatus': 'pending'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> permanentlyDeleteTask(String id) async {
    final db = await database;
    return await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<TaskModel?> getTask(String id) async {
    final db = await database;
    final maps = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return TaskModel.fromMap(maps.first);
  }

  Future<List<TaskModel>> getTasksForDate(DateTime date) async {
    final db = await database;
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
    final maps = await db.query(
      'tasks',
      where: 'createdAt >= ? AND createdAt <= ? AND isDeleted = 0',
      whereArgs: [start, end],
      orderBy: 'priority DESC, createdAt ASC',
    );
    return maps.map((m) => TaskModel.fromMap(m)).toList();
  }

  Future<List<TaskModel>> getAllActiveTasks() async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'isDeleted = 0',
      orderBy: 'priority DESC, createdAt ASC',
    );
    return maps.map((m) => TaskModel.fromMap(m)).toList();
  }

  Future<List<TaskModel>> getPendingTasks() async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'isCompleted = 0 AND isDeleted = 0',
      orderBy: 'priority DESC, createdAt ASC',
    );
    return maps.map((m) => TaskModel.fromMap(m)).toList();
  }

  Future<List<TaskModel>> getCompletedTasksForDate(DateTime date) async {
    final db = await database;
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
    final maps = await db.query(
      'tasks',
      where: 'isCompleted = 1 AND completedAt >= ? AND completedAt <= ? AND isDeleted = 0',
      whereArgs: [start, end],
      orderBy: 'completedAt DESC',
    );
    return maps.map((m) => TaskModel.fromMap(m)).toList();
  }

  Future<List<TaskModel>> getTasksWithReminders() async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'reminderTime IS NOT NULL AND isDeleted = 0',
    );
    return maps.map((m) => TaskModel.fromMap(m)).toList();
  }

  Future<int> toggleTaskCompletion(String id, bool completed) async {
    final db = await database;
    final result = await db.update(
      'tasks',
      {
        'isCompleted': completed ? 1 : 0,
        'completedAt': completed ? DateTime.now().toIso8601String() : null,
        'updatedAt': DateTime.now().toIso8601String(),
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _updateDailyCompletion();
    return result;
  }

  Future<void> _updateDailyCompletion() async {
    final db = await database;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).toIso8601String();
    final end = DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String();

    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM tasks WHERE createdAt >= ? AND createdAt <= ? AND isDeleted = 0',
      [start, end],
    );
    final completedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM tasks WHERE isCompleted = 1 AND completedAt >= ? AND completedAt <= ? AND isDeleted = 0',
      [start, end],
    );

    final total = (totalResult.first['count'] as int?) ?? 0;
    final completed = (completedResult.first['count'] as int?) ?? 0;
    final rate = total > 0 ? completed / total : 0.0;

    await db.insert(
      'daily_completions',
      {
        'id': '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
        'date': start,
        'totalTasks': total,
        'completedTasks': completed,
        'completionRate': rate,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TaskModel>> getRecurringTasks() async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'isRecurring = 1 AND isDeleted = 0',
    );
    return maps.map((m) => TaskModel.fromMap(m)).toList();
  }

  // ==================== DAILY COMPLETIONS ====================

  Future<void> upsertDailyCompletion(DailyCompletionModel completion) async {
    final db = await database;
    await db.insert(
      'daily_completions',
      completion.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DailyCompletionModel?> getDailyCompletion(DateTime date) async {
    final db = await database;
    final dateStr = DateTime(date.year, date.month, date.day).toIso8601String();
    final maps = await db.query(
      'daily_completions',
      where: 'date = ?',
      whereArgs: [dateStr],
    );
    if (maps.isEmpty) return null;
    return DailyCompletionModel.fromMap(maps.first);
  }

  Future<List<DailyCompletionModel>> getDailyCompletionsRange(DateTime start, DateTime end) async {
    final db = await database;
    final startStr = DateTime(start.year, start.month, start.day).toIso8601String();
    final endStr = DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String();
    final maps = await db.query(
      'daily_completions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'date ASC',
    );
    return maps.map((m) => DailyCompletionModel.fromMap(m)).toList();
  }

  // ==================== SYNC QUEUE ====================

  Future<void> addToSyncQueue(SyncQueueModel item) async {
    final db = await database;
    await db.insert('sync_queue', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SyncQueueModel>> getPendingSyncItems({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'sync_queue',
      where: 'isProcessed = 0 AND retryCount < 5',
      orderBy: 'createdAt ASC',
      limit: limit,
    );
    return maps.map((m) => SyncQueueModel.fromMap(m)).toList();
  }

  Future<void> markSyncItemProcessed(String id) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'isProcessed': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementRetryCount(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE sync_queue SET retryCount = retryCount + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> clearProcessedSyncItems() async {
    final db = await database;
    await db.delete('sync_queue', where: 'isProcessed = 1');
  }

  // ==================== ANALYTICS ====================

  Future<int> getTotalTasksCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM tasks WHERE isDeleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getCompletedTasksCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM tasks WHERE isCompleted = 1 AND isDeleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getCompletedTasksCountForDate(DateTime date) async {
    final db = await database;
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM tasks WHERE isCompleted = 1 AND completedAt >= ? AND completedAt <= ? AND isDeleted = 0',
      [start, end],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getStreakCount() async {
    final db = await database;
    final completions = await db.rawQuery(
      'SELECT date, completionRate FROM daily_completions ORDER BY date DESC'
    );
    if (completions.isEmpty) return 0;

    int streak = 0;
    DateTime currentDate = DateTime.now().dateOnly;
    bool checkedToday = false;

    for (final row in completions) {
      final date = DateTime.parse(row['date'] as String).dateOnly;
      final rate = row['completionRate'] as double;

      if (!checkedToday) {
        if (date.isAtSameMomentAs(currentDate) || date.isAtSameMomentAs(currentDate.subtract(const Duration(days: 1)))) {
          if (rate >= 0.5) {
            streak++;
            currentDate = date.subtract(const Duration(days: 1));
            checkedToday = true;
          } else {
            if (date.isAtSameMomentAs(currentDate)) {
              currentDate = date.subtract(const Duration(days: 1));
              checkedToday = true;
              continue;
            }
            break;
          }
        } else {
          break;
        }
        checkedToday = true;
      } else {
        if (date.isAtSameMomentAs(currentDate) && rate >= 0.5) {
          streak++;
          currentDate = date.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
    }
    return streak;
  }

  Future<double> getAverageCompletionRate() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT AVG(completionRate) as avg FROM daily_completions'
    );
    return (result.first['avg'] as double?) ?? 0.0;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

extension DateTimeExtension on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);
}
