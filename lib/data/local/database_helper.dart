import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/task_model.dart';
import '../models/task_log_model.dart';
import '../../core/utils/id_generator.dart';
import '../../core/extensions/date_extensions.dart';
import '../../core/utils/safe_parse.dart';
import '../models/daily_completion_model.dart';
import '../models/task_template_model.dart';
import '../models/badge_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  // Test injection: when set, [_initDatabase] uses this path instead of
  // the application documents directory. Tests should call [setTestDatabasePath]
  // before accessing the database and [resetTestDatabasePath] in tearDown.
  static String? _testDatabasePath;

  /// Sets a custom database file path for testing.
  static void setTestDatabasePath(String path) {
    _testDatabasePath = path;
  }

  /// Clears the test database path and forces the next access to reinitialize.
  static void resetTestDatabasePath() {
    _testDatabasePath = null;
  }

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = _testDatabasePath ??
        join((await getApplicationDocumentsDirectory()).path,
            'daily_tracker.db');

    return await openDatabase(
      path,
      version: 4,
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
        taskType TEXT DEFAULT 'checklist',
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
      CREATE TABLE IF NOT EXISTS task_logs (
        id TEXT PRIMARY KEY,
        taskId TEXT NOT NULL,
        date TEXT NOT NULL,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        completedAt TEXT,
        comment TEXT,
        mediaPath TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await db.execute('CREATE INDEX idx_tasks_date ON tasks(createdAt)');
    await db.execute('CREATE INDEX idx_tasks_completed ON tasks(isCompleted)');
    await db.execute('CREATE INDEX idx_tasks_deleted ON tasks(isDeleted)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_task_logs_task_date ON task_logs(taskId, date)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS task_logs (
          id TEXT PRIMARY KEY,
          taskId TEXT NOT NULL,
          date TEXT NOT NULL,
          isCompleted INTEGER NOT NULL DEFAULT 0,
          completedAt TEXT,
          comment TEXT,
          mediaPath TEXT,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          syncStatus TEXT NOT NULL DEFAULT 'pending'
        )
      ''');
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_task_logs_task_date ON task_logs(taskId, date)');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE tasks ADD COLUMN taskType TEXT DEFAULT \'checklist\'');
    }
    if (oldVersion < 4) {
      // Add sort order column to tasks
      await db.execute(
          'ALTER TABLE tasks ADD COLUMN sortIndex INTEGER NOT NULL DEFAULT 0');
      // Backfill sortIndex based on current ordering
      final rows = await db.query('tasks',
          orderBy: 'priority DESC, createdAt ASC', columns: ['id']);
      for (var i = 0; i < rows.length; i++) {
        await db.update('tasks', {'sortIndex': i},
            where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
      // Templates table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS task_templates (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          icon TEXT,
          isBuiltIn INTEGER NOT NULL DEFAULT 0,
          tasksJson TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
      // Badges table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS badges (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          threshold INTEGER NOT NULL,
          title TEXT NOT NULL,
          earnedAt TEXT
        )
      ''');
    }
  }

  // ==================== TASKS ====================

  Future<String> insertTask(TaskModel task) async {
    if (task.id.isEmpty) {
      throw ArgumentError('Task id cannot be empty');
    }
    if (task.title.isEmpty) {
      throw ArgumentError('Task title cannot be empty');
    }

    final db = await database;
    final id = await db.insert('tasks', task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
    if (id <= 0) {
      throw Exception('Failed to insert task: ${task.title}');
    }
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
    final result = await db.update(
      'tasks',
      {
        'isDeleted': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'syncStatus': 'pending'
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    // Recalculate today's completion stats since total task count changed
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _updateDailyCompletion(dateStr);
    return result;
  }

  Future<int> permanentlyDeleteTask(String id) async {
    final db = await database;
    await db.delete('task_logs', where: 'taskId = ?', whereArgs: [id]);
    return await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restoreTask(String id) async {
    final db = await database;
    await db.update(
      'tasks',
      {
        'isDeleted': 0,
        'updatedAt': DateTime.now().toIso8601String(),
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    // Recalculate stats for today since task count changed
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _updateDailyCompletion(dateStr);
  }

  Future<TaskModel?> getTask(String id) async {
    final db = await database;
    final maps = await db
        .query('tasks', where: 'id = ? AND isDeleted = 0', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return TaskModel.fromMap(maps.first);
  }

  Future<List<TaskModel>> getTasksForDate(DateTime date) async {
    final db = await database;
    // In a daily tracker, all active tasks apply to every day.
    // The 'date' parameter is kept for API compatibility and future per-date scheduling.
    final maps = await db.query(
      'tasks',
      where: 'isDeleted = 0',
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
    final end =
        DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
    final maps = await db.query(
      'tasks',
      where:
          'isCompleted = 1 AND completedAt >= ? AND completedAt <= ? AND isDeleted = 0',
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

  Future<int> updateTaskCompletion(TaskModel task) async {
    final db = await database;
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final result = await db.update(
      'tasks',
      {
        'isCompleted': task.isCompleted ? 1 : 0,
        'completedAt': task.completedAt?.toIso8601String(),
        'updatedAt': task.updatedAt.toIso8601String(),
        'syncStatus': task.syncStatus,
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );

    // Sync completion to today's task log
    final existing = await getTaskLog(task.id, dateStr);
    if (existing != null) {
      await updateTaskLog(existing.copyWith(
        isCompleted: task.isCompleted,
        completedAt: task.completedAt,
        updatedAt: now,
      ));
    } else {
      await insertTaskLog(TaskLogModel(
        id: IdGenerator.generate(),
        taskId: task.id,
        date: dateStr,
        isCompleted: task.isCompleted,
        completedAt: task.completedAt,
        createdAt: now,
        updatedAt: now,
      ));
    }

    await _updateDailyCompletion(dateStr);
    return result;
  }

  Future<void> _updateDailyCompletion(String dateStr) async {
    final db = await database;
    final parts =
        dateStr.split('-').map(int.tryParse).whereType<int>().toList();
    if (parts.length != 3) {
      throw FormatException(
          'Invalid date string for daily completion: $dateStr');
    }
    final year = parts[0];
    final month = parts[1];
    final day = parts[2];
    final start = DateTime(year, month, day).toIso8601String();
    final end = DateTime(year, month, day, 23, 59, 59).toIso8601String();

    // Count tasks that existed before end of today (created today or earlier) and not deleted
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM tasks WHERE createdAt <= ? AND isDeleted = 0',
      [end],
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
        'id': dateStr,
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

  Future<List<DailyCompletionModel>> getDailyCompletionsRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final startStr =
        DateTime(start.year, start.month, start.day).toIso8601String();
    final endStr =
        DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String();
    final maps = await db.query(
      'daily_completions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'date ASC',
    );
    return maps.map((m) => DailyCompletionModel.fromMap(m)).toList();
  }

  // ==================== ANALYTICS ====================

  Future<int> getTotalTasksCount() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT COUNT(*) as count FROM tasks WHERE isDeleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getCompletedTasksCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM tasks WHERE isCompleted = 1 AND isDeleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getCompletedTasksCountForDate(DateTime date) async {
    final db = await database;
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end =
        DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM tasks WHERE isCompleted = 1 AND completedAt >= ? AND completedAt <= ? AND isDeleted = 0',
      [start, end],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getStreakCount() async {
    final db = await database;
    final completions = await db.rawQuery(
        'SELECT date, completionRate FROM daily_completions ORDER BY date DESC');
    if (completions.isEmpty) return 0;

    int streak = 0;
    DateTime currentDate = DateTime.now().dateOnly;
    bool checkedToday = false;

    for (final row in completions) {
      final date = DateTime.tryParse(row['date'] as String? ?? '')?.dateOnly;
      if (date == null) continue;
      final rate = (row['completionRate'] as num?)?.toDouble() ?? 0.0;

      if (!checkedToday) {
        if (date.isAtSameMomentAs(currentDate) ||
            date.isAtSameMomentAs(
                currentDate.subtract(const Duration(days: 1)))) {
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
    final result = await db
        .rawQuery('SELECT AVG(completionRate) as avg FROM daily_completions');
    return (result.first['avg'] as double?) ?? 0.0;
  }

  Future<int> getBestStreakCount() async {
    final db = await database;
    final completions = await db.rawQuery(
        'SELECT date, completionRate FROM daily_completions ORDER BY date ASC');
    if (completions.isEmpty) return 0;

    int bestStreak = 0;
    int currentStreak = 0;
    DateTime? previousDate;

    for (final row in completions) {
      final date = DateTime.tryParse(row['date'] as String? ?? '')?.dateOnly;
      if (date == null) continue;
      final rate = (row['completionRate'] as num?)?.toDouble() ?? 0.0;

      if (rate >= 0.5) {
        if (previousDate == null || date.difference(previousDate).inDays == 1) {
          currentStreak++;
        } else {
          currentStreak = 1;
        }
        if (currentStreak > bestStreak) {
          bestStreak = currentStreak;
        }
      } else {
        currentStreak = 0;
      }
      previousDate = date;
    }
    return bestStreak;
  }

  Future<List<CategoryStat>> getCategoryStats() async {
    final db = await database;
    final tasksResult = await db.rawQuery(
        'SELECT category, COUNT(*) as total FROM tasks WHERE isDeleted = 0 GROUP BY category');
    final completedResult = await db.rawQuery(
        "SELECT category, COUNT(*) as completed FROM tasks WHERE isCompleted = 1 AND isDeleted = 0 GROUP BY category");

    final completedMap = {
      for (var row in completedResult)
        SafeParse.string(row['category'], defaultValue: 'Other'):
            SafeParse.integer(row['completed'])
    };

    return tasksResult.map((row) {
      final category = SafeParse.string(row['category'], defaultValue: 'Other');
      final total = SafeParse.integer(row['total']);
      final completed = completedMap[category] ?? 0;
      return CategoryStat(
          category: category, total: total, completed: completed);
    }).toList();
  }

  // ==================== TASK LOGS ====================

  Future<String> insertTaskLog(TaskLogModel log) async {
    final db = await database;
    await db.insert('task_logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
    return log.id;
  }

  Future<int> updateTaskLog(TaskLogModel log) async {
    final db = await database;
    return await db.update(
      'task_logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<TaskLogModel?> getTaskLog(String taskId, String date) async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      where: 'taskId = ? AND date = ?',
      whereArgs: [taskId, date],
    );
    if (maps.isEmpty) return null;
    return TaskLogModel.fromMap(maps.first);
  }

  Future<List<TaskLogModel>> getTaskLogsForTask(String taskId) async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      where: 'taskId = ?',
      whereArgs: [taskId],
      orderBy: 'date DESC',
    );
    return maps.map((m) => TaskLogModel.fromMap(m)).toList();
  }

  Future<List<TaskLogModel>> getTaskLogsForDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'createdAt ASC',
    );
    return maps.map((m) => TaskLogModel.fromMap(m)).toList();
  }

  Future<List<TaskLogModel>> getAllTaskLogs() async {
    final db = await database;
    final maps = await db.query(
      'task_logs',
      orderBy: 'date DESC',
    );
    return maps.map((m) => TaskLogModel.fromMap(m)).toList();
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  Future<void> wipeAllData() async {
    final db = await database;
    await db.delete('tasks');
    await db.delete('daily_completions');
    await db.delete('task_logs');
  }

  Future<List<DailyCompletionModel>> getDailyCompletionsInRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final startStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr =
        '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    final maps = await db.query(
      'daily_completions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'date ASC',
    );
    return maps.map((m) => DailyCompletionModel.fromMap(m)).toList();
  }

  // Template CRUD
  Future<List<TaskTemplateModel>> getTemplates() async {
    final db = await database;
    final maps = await db.query('task_templates',
        orderBy: 'isBuiltIn DESC, name ASC');
    return maps.map((m) => TaskTemplateModel.fromMap(m)).toList();
  }

  Future<void> upsertTemplate(TaskTemplateModel t) async {
    final db = await database;
    await db.insert('task_templates', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTemplate(String id) async {
    final db = await database;
    await db.delete('task_templates',
        where: 'id = ? AND isBuiltIn = 0', whereArgs: [id]);
  }

  // Badge CRUD
  Future<List<BadgeModel>> getBadges() async {
    final db = await database;
    final maps = await db.query('badges');
    return maps.map((m) => BadgeModel.fromMap(m)).toList();
  }

  Future<void> upsertBadge(BadgeModel b) async {
    final db = await database;
    await db.insert('badges', b.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Task ordering
  Future<void> updateTaskOrder(List<String> orderedIds) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update('tasks', {'sortIndex': i},
            where: 'id = ?', whereArgs: [orderedIds[i]]);
      }
    });
  }

  /// Atomically imports all data within a single SQLite transaction.
  /// If any insert fails, the entire import is rolled back.
  Future<void> importBatch({
    required List<TaskModel> tasks,
    required List<DailyCompletionModel> completions,
    required List<TaskLogModel> logs,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('tasks');
      await txn.delete('daily_completions');
      await txn.delete('task_logs');

      for (final task in tasks) {
        await txn.insert('tasks', task.toMap());
      }
      for (final completion in completions) {
        await txn.insert('daily_completions', completion.toMap());
      }
      for (final log in logs) {
        await txn.insert('task_logs', log.toMap());
      }
    });
  }
}

class CategoryStat {
  final String category;
  final int total;
  final int completed;

  CategoryStat(
      {required this.category, required this.total, required this.completed});

  double get completionRate => total > 0 ? completed / total : 0.0;
}
