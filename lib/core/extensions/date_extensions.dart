extension DateTimeExtensions on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);

  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }

  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return year == tomorrow.year &&
        month == tomorrow.month &&
        day == tomorrow.day;
  }

  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  String get formattedDate {
    return '$day ${_monthName(month)} $year';
  }

  String get formattedTime {
    final hour =
        this.hour > 12 ? this.hour - 12 : (this.hour == 0 ? 12 : this.hour);
    final period = this.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = minute.toString().padLeft(2, '0');
    return '$hour:$minuteStr $period';
  }

  String get formattedDateTime => '$formattedDate at $formattedTime';

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }
}
