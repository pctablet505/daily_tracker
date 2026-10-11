import '../core/day_key.dart';
import '../data/models.dart';

/// Pure rules for what one tap or one input writes. Each returns the entry to
/// store, or null to clear the day's entry.

Entry _make(
  Habit h,
  DayKey day,
  EntryState state,
  DateTime now, {
  double? value,
  String? note,
  String? photoPath,
}) => Entry(
  habitId: h.id,
  day: day,
  state: state,
  loggedAt: now,
  value: value,
  note: note,
  photoPath: photoPath,
);

String? _clean(String? text) {
  final t = text?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Tap on a tick habit: done, or off again if it already was.
Entry? tickEntry(Habit h, DayKey day, Entry? existing, DateTime now) {
  if (existing?.state == EntryState.done) return null;
  return _make(
    h,
    day,
    EntryState.done,
    now,
    note: existing?.note,
    photoPath: existing?.photoPath,
  );
}

/// An amount for a number habit: zero or less clears; short of the goal is
/// partial; at or past it (or any amount, when there is no goal) is done.
Entry? numberEntry(
  Habit h,
  DayKey day,
  double value,
  DateTime now, {
  Entry? existing,
}) {
  if (value <= 0) return null;
  final goal = h.goal;
  final state = goal != null && value < goal
      ? EntryState.partial
      : EntryState.done;
  return _make(
    h,
    day,
    state,
    now,
    value: value,
    note: existing?.note,
    photoPath: existing?.photoPath,
  );
}

Entry? noteEntry(
  Habit h,
  DayKey day,
  String text,
  DateTime now, {
  Entry? existing,
}) {
  final note = _clean(text);
  if (note == null) return null;
  return _make(
    h,
    day,
    EntryState.done,
    now,
    note: note,
    photoPath: existing?.photoPath,
  );
}

/// [fileName] is the photo's name inside the app's photo folder.
Entry photoEntry(
  Habit h,
  DayKey day,
  String fileName,
  DateTime now, {
  Entry? existing,
}) => _make(
  h,
  day,
  EntryState.done,
  now,
  note: existing?.note,
  photoPath: fileName,
);

/// Log a slip on a stay-clear habit; a second tap takes it back.
Entry? slipEntry(
  Habit h,
  DayKey day,
  Entry? existing,
  DateTime now, {
  String? note,
}) {
  if (existing?.state == EntryState.slipped) return null;
  return _make(h, day, EntryState.slipped, now, note: _clean(note));
}

/// Set a day aside on purpose; a second tap takes it back.
Entry? skipEntry(Habit h, DayKey day, Entry? existing, DateTime now) {
  if (existing?.state == EntryState.skipped) return null;
  return _make(h, day, EntryState.skipped, now);
}
