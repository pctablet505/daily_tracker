import '../data/models.dart';

/// The values on the add/edit screen, and the rules for turning them into a [Habit].
final class HabitForm {
  const HabitForm({
    this.name = '',
    this.description = '',
    this.kind = HabitKind.build,
    this.logType = LogType.tick,
    this.unit = '',
    this.goalText = '',
    this.daysMask = Habit.everyDay,
    this.dayPart = DayPart.anytime,
    this.reminderMinutes,
    this.area = '',
    this.avoidMode = AvoidMode.track,
  });

  static const maxNameLength = 60;

  factory HabitForm.fromHabit(Habit h) => HabitForm(
    name: h.name,
    description: h.description ?? '',
    kind: h.kind,
    logType: h.logType,
    unit: h.unit ?? '',
    goalText: h.goal == null ? '' : _goalText(h.goal!),
    daysMask: h.daysMask,
    dayPart: h.dayPart,
    reminderMinutes: h.reminderMinutes,
    area: h.area ?? '',
    avoidMode: h.avoidMode,
  );

  static String _goalText(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  final String name;
  final String description;
  final HabitKind kind;
  final LogType logType;
  final String unit;
  final String goalText;
  final int daysMask;
  final DayPart dayPart;
  final int? reminderMinutes;
  final String area;
  final AvoidMode avoidMode;

  /// An avoid habit that is ticked like a Do habit, or a Do habit.
  bool get logsSlips => kind == HabitKind.avoid && avoidMode == AvoidMode.track;
  bool get isNumber => !logsSlips && logType == LogType.number;

  String? get nameError {
    final n = name.trim();
    if (n.isEmpty) return 'Give it a name';
    if (n.length > maxNameLength)
      return 'Keep it under $maxNameLength characters';
    return null;
  }

  String? get daysError =>
      daysMask & Habit.everyDay == 0 ? 'Pick at least one day' : null;

  double? get goal {
    final t = goalText.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  String? get goalError {
    if (!isNumber) return null;
    if (goalText.trim().isEmpty) return null;
    final g = goal;
    return g == null || g <= 0 ? 'Enter a number above zero' : null;
  }

  bool get isValid =>
      nameError == null && daysError == null && goalError == null;

  /// Applies the form to [base] (a new habit's blank, or the one being edited). Only call when [isValid].
  Habit toHabit(Habit base) {
    String? clean(String s) => s.trim().isEmpty ? null : s.trim();
    final slips = logsSlips;
    final number = isNumber;
    return Habit(
      id: base.id,
      name: name.trim(),
      description: clean(description),
      kind: kind,
      logType: slips ? LogType.tick : logType,
      unit: number ? clean(unit) : null,
      goal: number ? goal : null,
      daysMask: daysMask & Habit.everyDay,
      dayPart: dayPart,
      reminderMinutes: slips ? null : reminderMinutes,
      area: clean(area),
      avoidMode: avoidMode,
      sortOrder: base.sortOrder,
      createdDay: base.createdDay,
      endDay: base.endDay,
    );
  }

  HabitForm copyWith({
    String? name,
    String? description,
    HabitKind? kind,
    LogType? logType,
    String? unit,
    String? goalText,
    int? daysMask,
    DayPart? dayPart,
    int? Function()? reminderMinutes,
    String? area,
    AvoidMode? avoidMode,
  }) => HabitForm(
    name: name ?? this.name,
    description: description ?? this.description,
    kind: kind ?? this.kind,
    logType: logType ?? this.logType,
    unit: unit ?? this.unit,
    goalText: goalText ?? this.goalText,
    daysMask: daysMask ?? this.daysMask,
    dayPart: dayPart ?? this.dayPart,
    reminderMinutes: reminderMinutes != null
        ? reminderMinutes()
        : this.reminderMinutes,
    area: area ?? this.area,
    avoidMode: avoidMode ?? this.avoidMode,
  );
}
