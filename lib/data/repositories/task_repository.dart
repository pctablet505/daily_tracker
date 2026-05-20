import 'dart:convert';
import '../../core/utils/id_generator.dart';
import '../local/database_helper.dart';
import '../models/task_model.dart';
import '../models/sync_queue_model.dart';

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
      priority: priority,
      syncStatus: 'pending',
    );

    await _db.insertTask(task);
    await _addToSyncQueue('create', task);
    return task;
  }

  Future<TaskModel> updateTask(TaskModel task, {
    String? title,
    String? description,
    DateTime? reminderTime,
    bool? isRecurring,
    String? recurrenceRule,
    String? category,
    int? priority,
  }) async {
    final updated = task.copyWith(
      title: title,
      description: description,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      priority: priority,
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    );

    await _db.updateTask(updated);
    await _addToSyncQueue('update', updated);
    return updated;
  }

  Future<void> deleteTask(String id) async {
    await _db.deleteTask(id);
    await _addToSyncQueue('delete', TaskModel(
      id: id,
      title: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    ));
  }

  Future<void> toggleTaskCompletion(TaskModel task) async {
    final newStatus = !task.isCompleted;
    await _db.toggleTaskCompletion(task.id, newStatus);
    final updated = task.copyWith(
      isCompleted: newStatus,
      completedAt: newStatus ? DateTime.now() : null,
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    );
    await _addToSyncQueue('update', updated);
  }

  Future<TaskModel?> getTask(String id) => _db.getTask(id);

  Future<List<TaskModel>> getTasksForDate(DateTime date) => _db.getTasksForDate(date);

  Future<List<TaskModel>> getAllActiveTasks() => _db.getAllActiveTasks();

  Future<List<TaskModel>> getPendingTasks() => _db.getPendingTasks();

  Future<List<TaskModel>> getCompletedTasksForDate(DateTime date) => _db.getCompletedTasksForDate(date);

  Future<List<TaskModel>> getTasksWithReminders() => _db.getTasksWithReminders();

  Future<List<TaskModel>> getRecurringTasks() => _db.getRecurringTasks();

  Future<void> _addToSyncQueue(String operation, TaskModel task) async {
    final queueItem = SyncQueueModel(
      id: IdGenerator.generate(),
      entityType: 'task',
      entityId: task.id,
      operation: operation,
      payload: jsonEncode(task.toMap()),
      createdAt: DateTime.now(),
    );
    await _db.addToSyncQueue(queueItem);
  }

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
          await _addToSyncQueue('update', resetTask);
        }
      }
    }
  }
}


