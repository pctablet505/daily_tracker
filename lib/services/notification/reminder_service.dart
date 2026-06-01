import '../../data/models/task_model.dart';
import 'notification_service.dart';
import 'quiet_hours_service.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final NotificationService _notifications = NotificationService();
  final QuietHoursService _quietHours = QuietHoursService();

  Future<void> scheduleTaskReminder(TaskModel task) async {
    if (task.reminderTime == null || task.isCompleted || task.isDeleted) {
      await cancelTaskReminder(task.id);
      return;
    }

    var reminderTime = task.reminderTime!;
    final now = DateTime.now();
    if (reminderTime.isBefore(now)) {
      if (task.isRecurring && task.recurrenceRule == 'daily') {
        // Reschedule for next occurrence (tomorrow at same time)
        reminderTime = DateTime(
          now.year, now.month, now.day,
          reminderTime.hour, reminderTime.minute, reminderTime.second,
        );
        if (!reminderTime.isAfter(now)) {
          reminderTime = reminderTime.add(const Duration(days: 1));
        }
      } else {
        await cancelTaskReminder(task.id);
        return;
      }
    }

    // Adjust for quiet hours
    reminderTime = await _quietHours.adjustForQuietHours(reminderTime);

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
    // Generate a stable, platform-independent integer hash from the task ID
    int hash = 0;
    for (int i = 0; i < taskId.length; i++) {
      hash = (31 * hash + taskId.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }
}
