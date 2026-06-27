import '../../core/utils/id_generator.dart';
import '../../core/extensions/date_extensions.dart';
import '../local/database_helper.dart';
import '../models/task_model.dart';
import '../models/task_log_model.dart';

class TaskRepository {
  final DatabaseHelper _db;

  TaskRepository(this._db);

  Future<TaskModel> createTask({
    required String title,
    String? description,
    DateTime? reminderTime,
    bool isRecurring = false,
    String? recurrenceRule,
    String? category,
    String? taskType,
    int priority = 0,
  }) async {
    final now = DateTime.now();
    final task = TaskModel(
      id: IdGenerator.generate(),
      title: title,
      description: description,
      createdAt: now,
      updatedAt: now,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      taskType: taskType ?? 'checklist',
      priority: priority,
      syncStatus: 'pending',
    );

    await _db.insertTask(task);
    return task;
  }

  Future<TaskModel> updateTask(
    TaskModel task, {
    String? title,
    String? description,
    DateTime? reminderTime,
    bool? isRecurring,
    String? recurrenceRule,
    String? category,
    String? taskType,
    int? priority,
  }) async {
    final updated = task.copyWith(
      title: title,
      description: description,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      taskType: taskType,
      priority: priority,
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    );

    await _db.updateTask(updated);
    return updated;
  }

  Future<void> deleteTask(String id) async {
    await _db.deleteTask(id);
  }

  Future<void> toggleTaskCompletion(TaskModel task) async {
    final now = DateTime.now();
    final updated = task.copyWith(
      isCompleted: !task.isCompleted,
      completedAt: !task.isCompleted ? now : null,
      updatedAt: now,
      syncStatus: 'pending',
    );
    await _db.updateTaskCompletion(updated);
  }

  Future<TaskModel?> getTask(String id) => _db.getTask(id);

  Future<List<TaskModel>> getTasksForDate(DateTime date) =>
      _db.getTasksForDate(date);

  Future<List<TaskModel>> getAllActiveTasks() => _db.getAllActiveTasks();

  Future<List<TaskModel>> getPendingTasks() => _db.getPendingTasks();

  Future<List<TaskModel>> getCompletedTasksForDate(DateTime date) =>
      _db.getCompletedTasksForDate(date);

  Future<List<TaskModel>> getTasksWithReminders() =>
      _db.getTasksWithReminders();

  Future<List<TaskModel>> getRecurringTasks() => _db.getRecurringTasks();

  // Recurring tasks reset
  Future<void> resetRecurringTasksForNewDay() async {
    final recurring = await _db.getRecurringTasks();
    final today = DateTime.now().dateOnly;

    for (final task in recurring) {
      if (task.isCompleted && task.completedAt != null) {
        final completedDate = task.completedAt!.dateOnly;
        if (!completedDate.isAtSameMomentAs(today)) {
          final resetTask = task.copyWith(
            isCompleted: false,
            completedAt: null,
            updatedAt: DateTime.now(),
            syncStatus: 'pending',
          );
          await _db.updateTask(resetTask);
        }
      }
    }
  }

  // Task Logs
  Future<TaskLogModel?> getTaskLog(String taskId, DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _db.getTaskLog(taskId, dateStr);
  }

  Future<List<TaskLogModel>> getTaskLogsForTask(String taskId) =>
      _db.getTaskLogsForTask(taskId);

  Future<void> saveTaskLog(TaskLogModel log) async {
    final existing = await _db.getTaskLog(log.taskId, log.date);
    if (existing != null) {
      await _db.updateTaskLog(
          log.copyWith(id: existing.id, updatedAt: DateTime.now()));
    } else {
      await _db.insertTaskLog(log);
    }
  }

  Future<List<TaskLogModel>> getAllTaskLogs() => _db.getAllTaskLogs();
}
