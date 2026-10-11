import '../core/day_key.dart';

/// `build`: something to do. `avoid`: something to stay clear of.
enum HabitKind { build, avoid }

/// How a habit is logged: a tap, a number, a short note or a photo.
enum LogType { tick, number, note, photo }

/// Where a habit sits in the day. Used to group the Today list.
enum DayPart { morning, afternoon, evening, anytime }

/// What happened on one day. `partial`: a number habit with progress short of
/// its goal. `skipped`: a day set aside on purpose (sick, travelling); it is
/// left out of rates and does not break a streak.
enum EntryState { done, partial, slipped, skipped }

/// Avoid habits only. `track`: the day starts on track and you log slips.
/// `confirm`: tick it yourself, like a build habit.
enum AvoidMode { track, confirm }

/// The value named [name]; [fallback] when the field is absent. A name that is
/// present but unknown throws, so a damaged backup is rejected rather than
/// read as something else.
T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('Unknown ${T.toString()} value', name.toString());
}

/// A thing you want to do (or avoid) on a schedule. Holds no per-day data.
final class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.createdDay,
    this.description,
    this.kind = HabitKind.build,
    this.logType = LogType.tick,
    this.unit,
    this.goal,
    this.daysMask = everyDay,
    this.dayPart = DayPart.anytime,
    this.reminderMinutes,
    this.area,
    this.avoidMode = AvoidMode.track,
    this.sortOrder = 0,
    this.endDay,
  });

  /// Bit 0 = Monday ... bit 6 = Sunday.
  static const everyDay = 127;
  static const weekdaysOnly = 31;

  final String id;
  final String name;
  final String? description;
  final HabitKind kind;
  final LogType logType;
  final String? unit;
  final double? goal;
  final int daysMask;
  final DayPart dayPart;

  /// Minutes after local midnight, or null for no reminder.
  final int? reminderMinutes;
  final String? area;
  final AvoidMode avoidMode;
  final int sortOrder;
  final DayKey createdDay;

  /// Last day this habit counts (inclusive); null while active.
  final DayKey? endDay;

  bool get isArchived => endDay != null;

  /// An avoid habit whose days start on track and where only slips are logged.
  bool get tracksSlips =>
      kind == HabitKind.avoid && avoidMode == AvoidMode.track;

  /// Whether the schedule includes [weekday] (1 = Monday ... 7 = Sunday).
  bool runsOn(int weekday) => (daysMask >> (weekday - 1)) & 1 == 1;

  /// The habit exists on [day]: from the day it was made to its last day.
  bool isActiveOn(DayKey day) =>
      day >= createdDay && (endDay == null || day <= endDay!);

  /// The habit is planned for [day].
  bool isScheduledOn(DayKey day) => isActiveOn(day) && runsOn(day.weekday);

  Habit copyWith({
    String? name,
    String? Function()? description,
    HabitKind? kind,
    LogType? logType,
    String? Function()? unit,
    double? Function()? goal,
    int? daysMask,
    DayPart? dayPart,
    int? Function()? reminderMinutes,
    String? Function()? area,
    AvoidMode? avoidMode,
    int? sortOrder,
    DayKey? createdDay,
    DayKey? Function()? endDay,
  }) => Habit(
    id: id,
    name: name ?? this.name,
    description: description != null ? description() : this.description,
    kind: kind ?? this.kind,
    logType: logType ?? this.logType,
    unit: unit != null ? unit() : this.unit,
    goal: goal != null ? goal() : this.goal,
    daysMask: daysMask ?? this.daysMask,
    dayPart: dayPart ?? this.dayPart,
    reminderMinutes: reminderMinutes != null
        ? reminderMinutes()
        : this.reminderMinutes,
    area: area != null ? area() : this.area,
    avoidMode: avoidMode ?? this.avoidMode,
    sortOrder: sortOrder ?? this.sortOrder,
    createdDay: createdDay ?? this.createdDay,
    endDay: endDay != null ? endDay() : this.endDay,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'kind': kind.name,
    'logType': logType.name,
    'unit': unit,
    'goal': goal,
    'daysMask': daysMask,
    'dayPart': dayPart.name,
    'reminderMinutes': reminderMinutes,
    'area': area,
    'avoidMode': avoidMode.name,
    'sortOrder': sortOrder,
    'createdDay': createdDay.toString(),
    'endDay': endDay?.toString(),
  };

  /// Throws [FormatException] when a required field is missing or malformed,
  /// so a corrupt backup is rejected instead of half-imported.
  factory Habit.fromMap(Map<String, Object?> m) {
    final id = m['id'];
    final name = m['name'];
    if (id is! String || id.isEmpty)
      throw const FormatException('Habit without id');
    if (name is! String || name.trim().isEmpty)
      throw FormatException('Habit without name', id);
    final created = m['createdDay'];
    if (created is! String)
      throw FormatException('Habit without createdDay', id);
    final end = m['endDay'];
    return Habit(
      id: id,
      name: name,
      description: m['description'] as String?,
      kind: _byName(HabitKind.values, m['kind'], HabitKind.build),
      logType: _byName(LogType.values, m['logType'], LogType.tick),
      unit: m['unit'] as String?,
      goal: (m['goal'] as num?)?.toDouble(),
      daysMask: (m['daysMask'] as num?)?.toInt() ?? everyDay,
      dayPart: _byName(DayPart.values, m['dayPart'], DayPart.anytime),
      reminderMinutes: (m['reminderMinutes'] as num?)?.toInt(),
      area: m['area'] as String?,
      avoidMode: _byName(AvoidMode.values, m['avoidMode'], AvoidMode.track),
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      createdDay: DayKey.parse(created),
      endDay: end is String ? DayKey.parse(end) : null,
    );
  }

  Object get _key => (
    id,
    name,
    description,
    kind,
    logType,
    unit,
    goal,
    daysMask,
    dayPart,
    reminderMinutes,
    area,
    avoidMode,
    sortOrder,
    createdDay,
    endDay,
  );

  @override
  bool operator ==(Object other) => other is Habit && other._key == _key;

  @override
  int get hashCode => _key.hashCode;

  @override
  String toString() => 'Habit($name)';
}

/// What happened for one habit on one day. At most one per (habit, day).
final class Entry {
  const Entry({
    required this.habitId,
    required this.day,
    required this.state,
    required this.loggedAt,
    this.value,
    this.note,
    this.photoPath,
  });

  final String habitId;
  final DayKey day;
  final EntryState state;
  final double? value;
  final String? note;
  final String? photoPath;
  final DateTime loggedAt;

  Entry copyWith({
    EntryState? state,
    double? Function()? value,
    String? Function()? note,
    String? Function()? photoPath,
    DateTime? loggedAt,
  }) => Entry(
    habitId: habitId,
    day: day,
    state: state ?? this.state,
    value: value != null ? value() : this.value,
    note: note != null ? note() : this.note,
    photoPath: photoPath != null ? photoPath() : this.photoPath,
    loggedAt: loggedAt ?? this.loggedAt,
  );

  Map<String, Object?> toMap() => {
    'habitId': habitId,
    'day': day.toString(),
    'state': state.name,
    'value': value,
    'note': note,
    'photoPath': photoPath,
    'loggedAt': loggedAt.toUtc().toIso8601String(),
  };

  factory Entry.fromMap(Map<String, Object?> m) {
    final habitId = m['habitId'];
    final day = m['day'];
    if (habitId is! String || habitId.isEmpty)
      throw const FormatException('Entry without habitId');
    if (day is! String) throw FormatException('Entry without day', habitId);
    final logged = m['loggedAt'];
    return Entry(
      habitId: habitId,
      day: DayKey.parse(day),
      state: _byName(EntryState.values, m['state'], EntryState.done),
      value: (m['value'] as num?)?.toDouble(),
      note: m['note'] as String?,
      photoPath: m['photoPath'] as String?,
      loggedAt:
          (logged is String ? DateTime.tryParse(logged) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Entry &&
      other.habitId == habitId &&
      other.day == day &&
      other.state == state &&
      other.value == value &&
      other.note == note &&
      other.photoPath == photoPath &&
      other.loggedAt.isAtSameMomentAs(loggedAt);

  @override
  int get hashCode => Object.hash(habitId, day, state, value, note, photoPath);

  @override
  String toString() => 'Entry($habitId, $day, ${state.name})';
}
