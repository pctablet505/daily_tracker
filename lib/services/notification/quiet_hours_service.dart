import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

class QuietHoursService {
  Future<bool> isInQuietHours(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString(AppConstants.prefQuietHoursStart);
    final endStr = prefs.getString(AppConstants.prefQuietHoursEnd);

    if (startStr == null || endStr == null) return false;

    final startParts = _parseTimeParts(startStr);
    final endParts = _parseTimeParts(endStr);
    if (startParts == null || endParts == null) return false;

    final startMinutes = startParts[0] * 60 + startParts[1];
    final endMinutes = endParts[0] * 60 + endParts[1];
    final timeMinutes = time.hour * 60 + time.minute;

    if (startMinutes <= endMinutes) {
      // Same day range (e.g., 22:00 - 07:00 would be cross-day)
      return timeMinutes >= startMinutes && timeMinutes < endMinutes;
    } else {
      // Cross-day range (e.g., 22:00 - 07:00)
      return timeMinutes >= startMinutes || timeMinutes < endMinutes;
    }
  }

  Future<DateTime> adjustForQuietHours(DateTime scheduledTime) async {
    if (!await isInQuietHours(scheduledTime)) return scheduledTime;

    final prefs = await SharedPreferences.getInstance();
    final endStr = prefs.getString(AppConstants.prefQuietHoursEnd);
    if (endStr == null) return scheduledTime;

    final endParts = _parseTimeParts(endStr);
    if (endParts == null) return scheduledTime;

    // Preserve seconds/milliseconds from original scheduled time
    var adjusted = DateTime(
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
      endParts[0],
      endParts[1],
      scheduledTime.second,
      scheduledTime.millisecond,
      scheduledTime.microsecond,
    );

    // If quiet hours end is before or at the same time as scheduled, move to next day
    if (!adjusted.isAfter(scheduledTime)) {
      adjusted = adjusted.add(const Duration(days: 1));
    }

    return adjusted;
  }

  /// Parses 'HH:MM' format safely. Returns null if malformed.
  List<int>? _parseTimeParts(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return null;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return [hour, minute];
    } catch (_) {
      return null;
    }
  }
}
