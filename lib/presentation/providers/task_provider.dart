import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/dependency_injection.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/task_model.dart';
import '../../data/models/task_log_model.dart';
import '../../data/repositories/task_repository.dart';
import '../../services/notification/reminder_service.dart';
import '../../services/media/media_service.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(getIt<DatabaseHelper>());
});

final tasksForDateProvider = FutureProvider.family<List<TaskModel>, DateTime>((ref, date) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTasksForDate(date);
});

final pendingTasksProvider = FutureProvider<List<TaskModel>>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getPendingTasks();
});

final completedTasksTodayProvider = FutureProvider<List<TaskModel>>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getCompletedTasksForDate(DateTime.now());
});

final tasksWithRemindersProvider = FutureProvider<List<TaskModel>>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTasksWithReminders();
});

final allTasksProvider = FutureProvider<List<TaskModel>>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getAllActiveTasks();
});

class TaskLogParam {
  final String taskId;
  final DateTime date;
  const TaskLogParam(this.taskId, this.date);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskLogParam &&
          runtimeType == other.runtimeType &&
          taskId == other.taskId &&
          date.year == other.date.year &&
          date.month == other.date.month &&
          date.day == other.date.day;

  @override
  int get hashCode => taskId.hashCode ^ date.year ^ date.month ^ date.day;
}

final taskLogProvider = FutureProvider.family<TaskLogModel?, TaskLogParam>((ref, param) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTaskLog(param.taskId, param.date);
});

final taskLogHistoryProvider = FutureProvider.family<List<TaskLogModel>, String>((ref, taskId) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTaskLogsForTask(taskId);
});

final allTaskLogsProvider = FutureProvider<List<TaskLogModel>>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getAllTaskLogs();
});

final taskActionsProvider = Provider<TaskActions>((ref) {
  return TaskActions(ref);
});

class TaskActions {
  final Ref ref;
  final ReminderService _reminderService = ReminderService();

  TaskActions(this.ref);

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
    final repository = ref.read(taskRepositoryProvider);
    final task = await repository.createTask(
      title: title,
      description: description,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      taskType: taskType,
      priority: priority,
    );
    await _reminderService.scheduleTaskReminder(task);
    refreshAllTaskProviders();
    return task;
  }

  Future<void> toggleCompletion(TaskModel task) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.toggleTaskCompletion(task);
    final updated = task.copyWith(isCompleted: !task.isCompleted);
    await _reminderService.scheduleTaskReminder(updated);
    refreshAllTaskProviders();
  }

  Future<void> deleteTask(String id) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.deleteTask(id);
    await _reminderService.cancelTaskReminder(id);
    refreshAllTaskProviders();
    _runMediaCleanup();
  }

  Future<TaskModel> updateTask(TaskModel task, {
    String? title,
    String? description,
    DateTime? reminderTime,
    bool? isRecurring,
    String? recurrenceRule,
    String? category,
    String? taskType,
    int? priority,
  }) async {
    final repository = ref.read(taskRepositoryProvider);
    final updated = await repository.updateTask(
      task,
      title: title,
      description: description,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      taskType: taskType,
      priority: priority,
    );
    await _reminderService.scheduleTaskReminder(updated);
    refreshAllTaskProviders();
    return updated;
  }

  Future<void> saveTaskLog(TaskLogModel log) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.saveTaskLog(log);
    ref.invalidate(taskLogProvider);
    ref.invalidate(taskLogHistoryProvider);
    ref.invalidate(allTaskLogsProvider);
    refreshAllTaskProviders();
    _runMediaCleanup();
  }

  Future<void> _runMediaCleanup() async {
    try {
      final repository = ref.read(taskRepositoryProvider);
      final logs = await repository.getAllTaskLogs();
      final activePaths = logs
          .map((l) => l.mediaPath)
          .where((path) => path != null && path.isNotEmpty)
          .cast<String>()
          .toList();
      await MediaService.cleanupUnusedMedia(activePaths);
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  void refreshAllTaskProviders() {
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);
    ref.invalidate(tasksForDateProvider(dateOnly));
    ref.invalidate(allTasksProvider);
    ref.invalidate(pendingTasksProvider);
    ref.invalidate(completedTasksTodayProvider);
    ref.invalidate(tasksWithRemindersProvider);
  }
}
