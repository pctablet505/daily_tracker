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

/// The day is no longer done. Whatever else it holds (an amount, a note or a
/// photo, e.g. from before the habit was edited to another log type) stays on
/// a partial entry, which counts as planned and not done: a tap never deletes
/// what was logged.
Entry? _undone(
  Habit h,
  DayKey day,
  DateTime now, {
  double? value,
  String? note,
  String? photoPath,
}) => value == null && note == null && photoPath == null
    ? null
    : _make(
        h,
        day,
        EntryState.partial,
        now,
        value: value,
        note: note,
        photoPath: photoPath,
      );

/// Tap on a tick habit: done, or off again if it already was.
Entry? tickEntry(Habit h, DayKey day, Entry? existing, DateTime now) {
  if (existing?.state == EntryState.done) {
    return _undone(
      h,
      day,
      now,
      value: existing!.value,
      note: existing.note,
      photoPath: existing.photoPath,
    );
  }
  return _make(
    h,
    day,
    EntryState.done,
    now,
    value: existing?.value,
    note: existing?.note,
    photoPath: existing?.photoPath,
  );
}

/// An amount for a number habit: zero or less clears it; short of the goal is
/// partial; at or past it (or any amount, when there is no goal) is done.
Entry? numberEntry(
  Habit h,
  DayKey day,
  double value,
  DateTime now, {
  Entry? existing,
}) {
  if (!value.isFinite || value <= 0) {
    return _undone(
      h,
      day,
      now,
      note: existing?.note,
      photoPath: existing?.photoPath,
    );
  }
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
  if (note == null) {
    return _undone(
      h,
      day,
      now,
      value: existing?.value,
      photoPath: existing?.photoPath,
    );
  }
  return _make(
    h,
    day,
    EntryState.done,
    now,
    value: existing?.value,
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
  value: existing?.value,
  note: existing?.note,
  photoPath: fileName,
);

/// Log a slip on a stay-clear habit; a second tap takes it back. A day taken
/// back that still holds an amount, a note or a photo is on track (done) with
/// them: taking a slip back never deletes what was logged.
Entry? slipEntry(
  Habit h,
  DayKey day,
  Entry? existing,
  DateTime now, {
  String? note,
}) {
  if (existing?.state == EntryState.slipped) {
    return existing!.value == null &&
            existing.note == null &&
            existing.photoPath == null
        ? null
        : _make(
            h,
            day,
            EntryState.done,
            now,
            value: existing.value,
            note: existing.note,
            photoPath: existing.photoPath,
          );
  }
  return _make(
    h,
    day,
    EntryState.slipped,
    now,
    value: existing?.value,
    note: _clean(note) ?? existing?.note,
    photoPath: existing?.photoPath,
  );
}

/// "I stayed clear" on a stay-clear habit's day the app did not see: that
/// habit, and no other, was on track. A day already logged stays as it is.
Entry stayedClearEntry(Habit h, DayKey day, Entry? existing, DateTime now) =>
    existing ?? _make(h, day, EntryState.done, now);

/// Whether the menu may offer "Skip this day" (or take a skip back). A day that
/// is done, partial or slipped stays as logged: a skip does not remember that
/// state, so taking it back could not restore a plain tick. Stay-clear days
/// start on track and are never set aside.
bool canSkipDay(Habit h, Entry? existing) =>
    existing == null ? !h.tracksSlips : existing.state == EntryState.skipped;

/// Set a day aside on purpose; a second tap takes it back. What was logged for
/// the day (an amount, a note, a photo) is kept while it is set aside, and comes
/// back with it.
Entry? skipEntry(Habit h, DayKey day, Entry? existing, DateTime now) {
  if (existing?.state != EntryState.skipped) {
    return _make(
      h,
      day,
      EntryState.skipped,
      now,
      value: existing?.value,
      note: existing?.note,
      photoPath: existing?.photoPath,
    );
  }
  final value = existing!.value;
  final photo = existing.photoPath;
  final note = existing.note;
  if (h.tracksSlips) {
    return note != null || value != null || photo != null
        ? _make(
            h,
            day,
            EntryState.slipped,
            now,
            value: value,
            note: note,
            photoPath: photo,
          )
        : null;
  }
  if (value != null && h.logType == LogType.number) {
    return numberEntry(h, day, value, now, existing: existing);
  }
  if (photo != null) return photoEntry(h, day, photo, now, existing: existing);
  if (note != null) return noteEntry(h, day, note, now, existing: existing);
  if (value != null) {
    return _make(
      h,
      day,
      EntryState.done,
      now,
      value: value,
      note: note,
      photoPath: photo,
    );
  }
  return null;
}
