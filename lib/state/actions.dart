import '../core/day_key.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../logic/logging.dart';
import '../services/photo_store.dart';

/// Everything the screens can do to stored data. Keeps the rules (what a tap
/// writes) in `logic/logging.dart` and the file clean-up for photos here.
final class HabitActions {
  HabitActions({
    required this.repo,
    required this.photos,
    required this._now,
    required this._newId,
  });

  final HabitRepository repo;
  final PhotoStore photos;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<Entry?> _existing(Habit h, DayKey day) async =>
      (await repo.entries(habitId: h.id, from: day, to: day)).firstOrNull;

  /// Stores [next] (or clears the day when null) and removes a photo file the
  /// day no longer points at.
  Future<void> _apply(Habit h, DayKey day, Entry? next, Entry? before) async {
    final Entry? replaced = next == null
        ? await repo.clearEntry(h.id, day)
        : await repo.setEntry(next);
    final old = replaced?.photoPath ?? before?.photoPath;
    if (old != null && old != next?.photoPath) await photos.delete(old);
  }

  Future<void> tick(Habit h, DayKey day) async {
    final before = await _existing(h, day);
    await _apply(h, day, tickEntry(h, day, before, _now()), before);
  }

  Future<void> logNumber(Habit h, DayKey day, double value) async {
    final before = await _existing(h, day);
    await _apply(
      h,
      day,
      numberEntry(h, day, value, _now(), existing: before),
      before,
    );
  }

  Future<void> logNote(Habit h, DayKey day, String text) async {
    final before = await _existing(h, day);
    await _apply(
      h,
      day,
      noteEntry(h, day, text, _now(), existing: before),
      before,
    );
  }

  /// Copies the picked photo into the app's folder, then records it. If
  /// recording fails the copy is removed again.
  Future<void> logPhoto(Habit h, DayKey day, String sourcePath) async {
    final name = await photos.importFile(sourcePath);
    try {
      final before = await _existing(h, day);
      await _apply(
        h,
        day,
        photoEntry(h, day, name, _now(), existing: before),
        before,
      );
    } catch (_) {
      await photos.delete(name);
      rethrow;
    }
  }

  Future<void> slip(Habit h, DayKey day, {String? note}) async {
    final before = await _existing(h, day);
    await _apply(h, day, slipEntry(h, day, before, _now(), note: note), before);
  }

  Future<void> skip(Habit h, DayKey day) async {
    final before = await _existing(h, day);
    await _apply(h, day, skipEntry(h, day, before, _now()), before);
  }

  Future<void> clear(Habit h, DayKey day) async =>
      _apply(h, day, null, await _existing(h, day));

  // Habits

  /// Stores a new habit (given a fresh id) starting [today].
  Future<Habit> addHabit(Habit draft, {required DayKey today}) {
    final h = Habit(
      id: _newId(),
      name: draft.name.trim(),
      description: draft.description,
      kind: draft.kind,
      logType: draft.logType,
      unit: draft.unit,
      goal: draft.goal,
      daysMask: draft.daysMask,
      dayPart: draft.dayPart,
      reminderMinutes: draft.reminderMinutes,
      area: draft.area,
      avoidMode: draft.avoidMode,
      createdDay: today,
    );
    return repo.addHabit(h);
  }

  Future<void> updateHabit(Habit h) => repo.updateHabit(h);

  /// Puts the habits in the order of [ids]; any habit not named goes after them.
  Future<void> reorder(List<String> ids, Iterable<String> allIds) =>
      repo.reorder([...ids, ...allIds.where((id) => !ids.contains(id))]);

  /// Takes the habit off the lists from today on; its history stays.
  Future<void> archive(Habit h, DayKey today) =>
      repo.archive(h.id, today.addDays(-1));

  Future<Habit> startAgain(Habit archived, DayKey today) =>
      repo.startAgain(archived, newId: _newId(), today: today);

  Future<DeletedHabit> deleteHabit(String id) => repo.deleteHabit(id);

  Future<void> undoDelete(DeletedHabit gone) => repo.restoreHabit(gone);

  /// Call once the undo window has passed: only then are the photo files removed.
  Future<void> finishDelete(DeletedHabit gone) async {
    for (final e in gone.entries) {
      final name = e.photoPath;
      if (name != null) await photos.delete(name);
    }
  }

  Future<void> markSeen(DayKey day) => repo.markSeen(day);
}
