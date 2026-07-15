import '../../data/models/task_model.dart';
import '../../domain/entities/recurrence_rule.dart';
import '../../core/extensions/date_extensions.dart';
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
    final rule = RecurrenceRule.decode(task.recurrenceRule);

    // For recurring tasks, schedule the next occurrence. If the user picked a
    // future date that does not satisfy the rule, the date is advanced to the
    // next matching day. This is simpler than maintaining per-day scheduled
    // checks and self-cancelling on off days.
    if (task.isRecurring && rule.type != RecurrenceType.none) {
      final start = reminderTime.isBefore(now) ? now : reminderTime;
      final next = _nextOccurringDateTime(
        rule: rule,
        anchor: task.createdAt,
        from: start,
        reminderTime: reminderTime,
      );
      if (next == null) {
        await cancelTaskReminder(task.id);
        return;
      }
      reminderTime = next;
    } else if (reminderTime.isBefore(now)) {
      await cancelTaskReminder(task.id);
      return;
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

  /// Finds the next date on or after [from] that satisfies [rule], anchored to
  /// the task creation date, and returns a [DateTime] with the same time-of-day
  /// as the original reminder. Returns `null` if no occurrence is found within
  /// one year (defensive guard for malformed rules).
  DateTime? _nextOccurringDateTime({
    required RecurrenceRule rule,
    required DateTime anchor,
    required DateTime from,
    required DateTime reminderTime,
  }) {
    final start = from.dateOnly;
    final limit = start.add(const Duration(days: 365));
    var candidateDate = start;

    while (!candidateDate.isAfter(limit)) {
      if (rule.occursOn(candidateDate, anchor: anchor.dateOnly)) {
        final candidate = DateTime(
          candidateDate.year,
          candidateDate.month,
          candidateDate.day,
          reminderTime.hour,
          reminderTime.minute,
          reminderTime.second,
        );
        if (candidate.isAfter(DateTime.now())) {
          return candidate;
        }
      }
      candidateDate = candidateDate.add(const Duration(days: 1));
    }

    return null;
  }
}
