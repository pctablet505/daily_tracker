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
  static const maxAreaLength = 40;
  static const maxUnitLength = 12;
  static const maxDescriptionLength = 200;
  static const maxGoal = 9999999.99;

  factory HabitForm.fromHabit(Habit h) {
    final rem = h.reminderMinutes;
    final mask = h.daysMask & Habit.everyDay;
    return HabitForm(
      name: h.name,
      description: h.description ?? '',
      kind: h.kind,
      logType: h.logType,
      unit: h.unit ?? '',
      goalText: h.goal == null ? '' : _goalText(h.goal!),
      daysMask: mask == 0 ? Habit.everyDay : mask,
      dayPart: h.dayPart,
      reminderMinutes: rem != null && rem >= 0 && rem < 24 * 60 ? rem : null,
      area: h.area ?? '',
      avoidMode: h.avoidMode,
    );
  }

  static String _goalText(double v) =>
      v.isFinite && v.abs() < 1e15 && v == v.roundToDouble()
      ? v.round().toString()
      : v.toString();

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

  static String? _tooLong(String text, int max) =>
      text.trim().length > max ? 'Keep it under $max characters' : null;

  String? get areaError => _tooLong(area, maxAreaLength);

  /// Only a number habit keeps its unit.
  String? get unitError => isNumber ? _tooLong(unit, maxUnitLength) : null;

  String? get descriptionError => _tooLong(description, maxDescriptionLength);

  String? get daysError => logsSlips
      ? null
      : (daysMask & Habit.everyDay == 0 ? 'Pick at least one day' : null);

  /// "10000", "10,000" (thousands) and "2,5" (decimal comma) all read as expected.
  double? get goal {
    final t = goalText.trim();
    if (t.isEmpty) return null;
    final grouped = RegExp(r'^[1-9]\d{0,2}(,\d{3})+(\.\d+)?$').hasMatch(t);
    final v = double.tryParse(
      grouped ? t.replaceAll(',', '') : t.replaceAll(',', '.'),
    );
    return v != null && v.isFinite ? v : null;
  }

  String? get goalError {
    if (!isNumber) return null;
    if (goalText.trim().isEmpty) return null;
    final g = goal;
    if (g == null || g <= 0) return 'Enter a number above zero';
    if ((g * 100 - (g * 100).round()).abs() > 1e-6) {
      return 'Use at most 2 decimal places';
    }
    if (g > maxGoal) return 'Keep it under 10,000,000';
    return null;
  }

  bool get isValid =>
      nameError == null &&
      daysError == null &&
      goalError == null &&
      areaError == null &&
      unitError == null &&
      descriptionError == null;

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
      daysMask: slips ? Habit.everyDay : (daysMask & Habit.everyDay),
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
