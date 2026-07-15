import '../../core/extensions/date_extensions.dart';

/// The supported recurrence shapes.
enum RecurrenceType {
  /// Not recurring. [occursOn] still returns `true` so that a non-recurring
  /// task appears on every day (matching legacy behavior).
  none,

  /// Repeats every day.
  daily,

  /// Repeats on a fixed set of weekdays (1 = Monday … 7 = Sunday).
  weekly,

  /// A target number of completions per week. The count is intentionally not
  /// enforced as a fixed-day schedule here; [occursOn] returns `true` every
  /// day so the task is always available. Completion counting is handled by
  /// analytics, not by this engine.
  timesPerWeek,

  /// Repeats every [interval] days, anchored to the task creation date.
  everyNDays,
}

/// A compact, pure-Dart value type that describes how a task repeats.
///
/// The string format stored in SQLite is intentionally simple and backward
/// compatible with the legacy `'daily'` value:
///
///   * `daily`
///   * `weekly:1,3,5`
///   * `timesPerWeek:3`
///   * `everyNDays:2`
class RecurrenceRule {
  final RecurrenceType type;
  final Set<int> weekdays;
  final int? count;
  final int? interval;

  const RecurrenceRule._({
    required this.type,
    this.weekdays = const {},
    this.count,
    this.interval,
  });

  const RecurrenceRule.none() : this._(type: RecurrenceType.none);

  const RecurrenceRule.daily() : this._(type: RecurrenceType.daily);

  RecurrenceRule.weekly(Set<int> weekdays)
      : this._(
          type: RecurrenceType.weekly,
          weekdays: Set.unmodifiable(
            weekdays.where((d) => d >= 1 && d <= 7).toSet(),
          ),
        );

  RecurrenceRule.timesPerWeek(int count)
      : this._(
          type: RecurrenceType.timesPerWeek,
          count: count.clamp(1, 7),
        );

  RecurrenceRule.everyNDays(int interval)
      : this._(
          type: RecurrenceType.everyNDays,
          interval: interval < 1 ? 1 : interval,
        );

  /// Encodes this rule to the compact string format used in the database.
  String encode() {
    switch (type) {
      case RecurrenceType.none:
        return '';
      case RecurrenceType.daily:
        return 'daily';
      case RecurrenceType.weekly:
        final sorted = weekdays.toList()..sort();
        return 'weekly:${sorted.join(',')}';
      case RecurrenceType.timesPerWeek:
        return 'timesPerWeek:$count';
      case RecurrenceType.everyNDays:
        return 'everyNDays:$interval';
    }
  }

  /// Decodes a raw database value into a [RecurrenceRule].
  ///
  /// Returns [RecurrenceRule.none] for null, empty, or malformed input.
  static RecurrenceRule decode(String? raw) {
    if (raw == null) return const RecurrenceRule.none();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const RecurrenceRule.none();

    if (trimmed == 'daily') return const RecurrenceRule.daily();

    if (trimmed.startsWith('weekly:')) {
      final payload = trimmed.substring('weekly:'.length);
      final days = <int>{};
      for (final part in payload.split(',')) {
        final value = int.tryParse(part.trim());
        if (value != null && value >= 1 && value <= 7) {
          days.add(value);
        }
      }
      if (days.isEmpty) return const RecurrenceRule.none();
      return RecurrenceRule.weekly(days);
    }

    if (trimmed.startsWith('timesPerWeek:')) {
      final payload = trimmed.substring('timesPerWeek:'.length).trim();
      final value = int.tryParse(payload);
      if (value == null || value < 1 || value > 7) {
        return const RecurrenceRule.none();
      }
      return RecurrenceRule.timesPerWeek(value);
    }

    if (trimmed.startsWith('everyNDays:')) {
      final payload = trimmed.substring('everyNDays:'.length).trim();
      final value = int.tryParse(payload);
      if (value == null || value < 1) return const RecurrenceRule.none();
      return RecurrenceRule.everyNDays(value);
    }

    return const RecurrenceRule.none();
  }

  /// Returns `true` if this rule says the task should appear on [day].
  ///
  /// [anchor] is the task's creation date (date-only). For non-recurring
  /// tasks ([RecurrenceType.none]) the result is always `true`, preserving
  /// the legacy behavior of showing every active task on every day.
  bool occursOn(DateTime day, {required DateTime anchor}) {
    final target = day.dateOnly;
    final anchorDate = anchor.dateOnly;

    switch (type) {
      case RecurrenceType.none:
      case RecurrenceType.daily:
      case RecurrenceType.timesPerWeek:
        return true;
      case RecurrenceType.weekly:
        return weekdays.contains(target.weekday);
      case RecurrenceType.everyNDays:
        if (target.isBefore(anchorDate)) return false;
        final diff = target.difference(anchorDate).inDays;
        return diff % interval! == 0;
    }
  }

  /// A human-readable description suitable for UI labels.
  String describe() {
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    switch (type) {
      case RecurrenceType.none:
        return 'Does not repeat';
      case RecurrenceType.daily:
        return 'Every day';
      case RecurrenceType.weekly:
        if (weekdays.isEmpty) return 'Does not repeat';
        final sorted = weekdays.toList()..sort();
        return sorted.map((d) => weekdayNames[d - 1]).join(', ');
      case RecurrenceType.timesPerWeek:
        return '$count× per week';
      case RecurrenceType.everyNDays:
        return interval == 1 ? 'Every day' : 'Every $interval days';
    }
  }

  RecurrenceRule copyWith({
    RecurrenceType? type,
    Set<int>? weekdays,
    int? count,
    int? interval,
  }) {
    return RecurrenceRule._(
      type: type ?? this.type,
      weekdays: weekdays ?? this.weekdays,
      count: count ?? this.count,
      interval: interval ?? this.interval,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecurrenceRule &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          _setsEqual(weekdays, other.weekdays) &&
          count == other.count &&
          interval == other.interval;

  @override
  int get hashCode => Object.hash(type, weekdays, count, interval);

  @override
  String toString() =>
      'RecurrenceRule(type: $type, weekdays: $weekdays, count: $count, interval: $interval)';

  static bool _setsEqual(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }
}
