import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/app_logger.dart';
import '../../core/services/dependency_injection.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/task_model.dart';
import '../../data/models/task_log_model.dart';
import '../../data/repositories/task_repository.dart';
import '../../services/notification/reminder_service.dart';
import '../../services/media/media_service.dart';
import '../../data/models/task_template_model.dart';
import '../../data/models/badge_model.dart';
import '../../data/models/daily_completion_model.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(getIt<DatabaseHelper>());
});

final tasksForDateProvider =
    FutureProvider.family<List<TaskModel>, DateTime>((ref, date) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTasksForDate(date);
});

final pendingTasksProvider = FutureProvider<List<TaskModel>>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getPendingTasks();
});

final completedTasksTodayProvider =
    FutureProvider<List<TaskModel>>((ref) async {
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

final taskLogProvider =
    FutureProvider.family<TaskLogModel?, TaskLogParam>((ref, param) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTaskLog(param.taskId, param.date);
});

final taskLogHistoryProvider =
    FutureProvider.family<List<TaskLogModel>, String>((ref, taskId) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getTaskLogsForTask(taskId);
});

final allTaskLogsProvider = FutureProvider<List<TaskLogModel>>((ref) async {
  final repository = ref.watch(taskRepositoryProvider);
  return repository.getAllTaskLogs();
});

final templatesProvider = FutureProvider<List<TaskTemplateModel>>((ref) async {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.getTemplates();
});

final badgesProvider = FutureProvider<List<BadgeModel>>((ref) async {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.getBadges();
});

final monthCompletionsProvider = FutureProvider.family<
    Map<DateTime, DailyCompletionModel>, DateTime>((ref, month) async {
  final repo = ref.watch(taskRepositoryProvider);
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 0);
  final list = await repo.getDailyCompletionsInRange(start, end);
  return {
    for (final c in list)
      DateTime(c.date.year, c.date.month, c.date.day): c
  };
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
    // Always refresh UI even if reminder scheduling fails
    refreshAllTaskProviders();
    // Schedule reminder separately so failures don't break task creation
    try {
      await _reminderService.scheduleTaskReminder(task);
    } catch (e) {
      AppLogger.e('Reminder scheduling failed for task ${task.id}', e);
    }
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
    ref.invalidate(taskLogProvider);
    ref.invalidate(taskLogHistoryProvider);
    ref.invalidate(allTaskLogsProvider);
    await _runMediaCleanup();
  }

  Future<void> restoreTask(String id) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.restoreTask(id);
    refreshAllTaskProviders();
  }

  Future<void> cleanupUnusedMedia() => _runMediaCleanup();

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
    await _runMediaCleanup();
  }

  Future<void> _runMediaCleanup() async {
    final repository = ref.read(taskRepositoryProvider);
    final logs = await repository.getAllTaskLogs();
    final activePaths = logs
        .map((l) => l.mediaPath)
        .where((path) => path != null && path.isNotEmpty)
        .cast<String>()
        .toList();
    await MediaService.cleanupUnusedMedia(activePaths);
  }

  void refreshAllTaskProviders() {
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);
    ref.invalidate(tasksForDateProvider(dateOnly));
    ref.invalidate(allTasksProvider);
    ref.invalidate(pendingTasksProvider);
    ref.invalidate(completedTasksTodayProvider);
    ref.invalidate(tasksWithRemindersProvider);
    ref.invalidate(templatesProvider);
  }
}
