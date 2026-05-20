import '../../data/models/task_model.dart';
import 'notification_service.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final NotificationService _notifications = NotificationService();

  Future<void> scheduleTaskReminder(TaskModel task) async {
    if (task.reminderTime == null || task.isCompleted || task.isDeleted) {
      await cancelTaskReminder(task.id);
      return;
    }

    final reminderTime = task.reminderTime!;
    if (reminderTime.isBefore(DateTime.now())) {
      await cancelTaskReminder(task.id);
      return;
    }

    final notificationId = _generateNotificationId(task.id);

    await _notifications.scheduleTaskReminder(
      id: notificationId,
      title: 'Task Reminder',
      body: task.title,
      scheduledDate: reminderTime,
    );
  }

  Future<void> cancelTaskReminder(String taskId) async {
    final notificationId = _generateNotificationId(taskId);
    await _notifications.cancelReminder(notificationId);
  }

  Future<void> rescheduleAllReminders(List<TaskModel> tasks) async {
    await _notifications.cancelAllReminders();
    for (final task in tasks) {
      await scheduleTaskReminder(task);
    }
  }

  int _generateNotificationId(String taskId) {
    // Generate a stable integer hash from the task ID
    return taskId.hashCode.abs() % 2147483647;
  }
}
