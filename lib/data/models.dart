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

/// A JSON number as a double. Infinity (what `1e400` parses to) is damage, not data.
double? _finite(Object? v) {
  if (v == null) return null;
  if (v is! num || !v.isFinite) throw FormatException('Bad number', '$v');
  return v.toDouble();
}

/// The largest whole number a JSON number (a double) holds exactly.
const _maxWhole = 0x1fffffffffffff;

int? _wholeNumber(Object? v) {
  final d = _finite(v);
  if (d == null) return null;
  if (d != d.truncateToDouble() || d.abs() > _maxWhole) {
    throw FormatException('Bad whole number', '$v');
  }
  return d.toInt();
}

/// A stored number column, or null when it holds no usable number.
double? _storedNumber(Object? v) =>
    v is num && v.isFinite ? v.toDouble() : null;

int? _storedWhole(Object? v) => v is int ? v : _storedNumber(v)?.toInt();

String? _optString(Object? v) {
  if (v == null) return null;
  if (v is! String) throw FormatException('Bad text field', '$v');
  return v;
}

/// A photo's name inside the photo folder. Anything that could point elsewhere
/// is damage: a backup must never reach outside that folder.
String? _photoName(Object? v) {
  if (v == null) return null;
  if (!_isPhotoName(v)) throw FormatException('Bad photo name', '$v');
  return v as String;
}

bool _isPhotoName(Object? v) =>
    v is String &&
    v.trim().isNotEmpty &&
    v == v.trim() &&
    !v.startsWith('.') &&
    !v.contains('/') &&
    !v.contains('\\') &&
    !v.contains(':') &&
    !v.contains('\x00');

/// No phone dates a day before this. 2.0.2 and 2.0.3 stored earlier days a
/// crafted backup held; such a day reads as this one, so a backup made from
/// the database is one this version takes back.
const earliestDay = DayKey(1970, 1, 1);

/// A day as stored in the database, held to no earlier than [earliestDay].
DayKey storedDay(String text) {
  final day = DayKey.parse(text);
  return day < earliestDay ? earliestDay : day;
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
  factory Habit.fromMap(Map<String, Object?> m) => Habit._read(m, mend: false);

  /// Reads a database row. A value an older version stored that [fromMap] now
  /// refuses is mended instead, so one odd row cannot stop the app loading.
  factory Habit.fromRow(Map<String, Object?> r) => Habit._read(r, mend: true);

  factory Habit._read(Map<String, Object?> m, {required bool mend}) {
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
    if (end != null && end is! String) {
      throw FormatException('Habit with bad endDay', id);
    }
    final createdDay = mend ? storedDay(created) : DayKey.parse(created);
    var endDay = end is String ? DayKey.parse(end) : null;
    // 2.0.2 archived a habit as ending the day before "today", even when the
    // phone's date was before its start: it never ran, which is this end.
    if (endDay != null && endDay < createdDay.addDays(-1)) {
      endDay = createdDay.addDays(-1);
    }
    var daysMask = mend
        ? (_storedWhole(m['daysMask']) ?? everyDay) & everyDay
        : _wholeNumber(m['daysMask']) ?? everyDay;
    if (daysMask < 1 || daysMask > everyDay) {
      if (!mend) throw FormatException('Habit with bad daysMask', id);
      daysMask = everyDay;
    }
    var goal = mend ? _storedNumber(m['goal']) : _finite(m['goal']);
    if (goal != null && goal <= 0) {
      if (!mend) throw FormatException('Habit with non-positive goal', id);
      goal = null;
    }
    final rawReminder = mend
        ? _storedWhole(m['reminderMinutes'])
        : _wholeNumber(m['reminderMinutes']);
    final reminderMinutes =
        rawReminder != null && rawReminder >= 0 && rawReminder < 24 * 60
        ? rawReminder
        : null;
    return Habit(
      id: id,
      name: name,
      description: _optString(m['description']),
      kind: _byName(HabitKind.values, m['kind'], HabitKind.build),
      logType: _byName(LogType.values, m['logType'], LogType.tick),
      unit: _optString(m['unit']),
      goal: goal,
      daysMask: daysMask,
      dayPart: _byName(DayPart.values, m['dayPart'], DayPart.anytime),
      reminderMinutes: reminderMinutes,
      area: _optString(m['area']),
      avoidMode: _byName(AvoidMode.values, m['avoidMode'], AvoidMode.track),
      sortOrder: mend
          ? (_storedWhole(m['sortOrder']) ?? 0).clamp(-_maxWhole, _maxWhole)
          : _wholeNumber(m['sortOrder']) ?? 0,
      createdDay: createdDay,
      endDay: endDay,
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

  /// Throws [FormatException] when a field is missing or malformed, like
  /// [Habit.fromMap].
  factory Entry.fromMap(Map<String, Object?> m) => Entry._read(m, mend: false);

  /// Reads a database row, mending what an older version stored, like
  /// [Habit.fromRow]. The entry itself always stays.
  factory Entry.fromRow(Map<String, Object?> r) => Entry._read(r, mend: true);

  factory Entry._read(Map<String, Object?> m, {required bool mend}) {
    final habitId = m['habitId'];
    final dayText = m['day'];
    if (habitId is! String || habitId.isEmpty)
      throw const FormatException('Entry without habitId');
    if (dayText is! String) throw FormatException('Entry without day', habitId);
    final day = mend ? storedDay(dayText) : DayKey.parse(dayText);
    final logged = m['loggedAt'];
    if (!mend && logged != null && logged is! String) {
      throw FormatException('Entry with bad loggedAt', habitId);
    }
    final parsedLogged = logged is String ? DateTime.tryParse(logged) : null;
    if (!mend && logged is String && parsedLogged == null) {
      throw FormatException('Entry with unparseable loggedAt', habitId);
    }
    var value = mend ? _storedNumber(m['value']) : _finite(m['value']);
    if (value != null && value < 0) {
      if (!mend) throw FormatException('Entry with negative value', habitId);
      value = null;
    }
    final photo = m['photoPath'];
    return Entry(
      habitId: habitId,
      day: day,
      state: _byName(EntryState.values, m['state'], EntryState.done),
      value: value,
      note: _optString(m['note']),
      photoPath: mend
          ? (_isPhotoName(photo) ? photo! as String : null)
          : _photoName(photo),
      loggedAt:
          parsedLogged ??
          (mend
              ? DateTime.utc(day.year, day.month, day.day)
              : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
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
