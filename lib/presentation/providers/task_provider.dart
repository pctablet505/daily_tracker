import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/dependency_injection.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/task_model.dart';
import '../../data/repositories/task_repository.dart';
import '../../services/notification/reminder_service.dart';

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

final taskActionsProvider = Provider<TaskActions>((ref) {
  return TaskActions(ref);
});

class TaskActions {
  final ProviderRef ref;
  final ReminderService _reminderService = ReminderService();

  TaskActions(this.ref);

  Future<TaskModel> createTask({
    required String title,
    String? description,
    DateTime? reminderTime,
    bool isRecurring = false,
    String? recurrenceRule,
    String? category,
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
      priority: priority,
    );
    await _reminderService.scheduleTaskReminder(task);
    _refreshTasks();
    return task;
  }

  Future<void> toggleCompletion(TaskModel task) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.toggleTaskCompletion(task);
    final updated = task.copyWith(isCompleted: !task.isCompleted);
    await _reminderService.scheduleTaskReminder(updated);
    _refreshTasks();
  }

  Future<void> deleteTask(String id) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.deleteTask(id);
    await _reminderService.cancelTaskReminder(id);
    _refreshTasks();
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
    final repository = ref.read(taskRepositoryProvider);
    final updated = await repository.updateTask(
      task,
      title: title,
      description: description,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      priority: priority,
    );
    await _reminderService.scheduleTaskReminder(updated);
    _refreshTasks();
    return updated;
  }

  void _refreshTasks() {
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);
    ref.invalidate(tasksForDateProvider(dateOnly));
    ref.invalidate(pendingTasksProvider);
    ref.invalidate(completedTasksTodayProvider);
    ref.invalidate(tasksWithRemindersProvider);
  }
}
