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
    Future<Set<String>?> Function()? keptBySafetyCopies,
  }) : _keptBySafetyCopies = keptBySafetyCopies ?? _noSafetyCopies;

  final HabitRepository repo;
  final PhotoStore photos;
  final DateTime Function() _now;
  final String Function() _newId;

  /// The photo names the copies saved before restores refer to, or null when
  /// a copy cannot be read. "Undo the last restore" needs those photos.
  final Future<Set<String>?> Function() _keptBySafetyCopies;

  static Future<Set<String>?> _noSafetyCopies() async => const {};

  /// Deleted habits whose undo window is still open.
  final _undoable = <DeletedHabit>[];

  Future<Entry?> _existing(Habit h, DayKey day) async =>
      (await repo.entries(habitId: h.id, from: day, to: day)).firstOrNull;

  /// Every photo something may still show, or null when that is not known
  /// for sure. Entries are read before the safety copies: a restore saves its
  /// copy before it replaces the entries, so a photo is always in one of them.
  Future<Set<String>?> _photosInUse() async {
    final live = {
      for (final e in await repo.entries())
        if (e.photoPath != null) e.photoPath!,
      for (final gone in _undoable)
        for (final e in gone.entries)
          if (e.photoPath != null) e.photoPath!,
    };
    final kept = await _keptBySafetyCopies();
    return kept == null ? null : {...live, ...kept};
  }

  Future<void> _deleteIfUnreferenced(String name) async {
    final inUse = await _photosInUse();
    if (inUse != null && !inUse.contains(name)) await photos.delete(name);
  }

  /// Stores [next] (or clears the day when null) and removes a photo file the
  /// day no longer points at.
  Future<void> _apply(Habit h, DayKey day, Entry? next, Entry? before) async {
    final Entry? replaced = next == null
        ? await repo.clearEntry(h.id, day)
        : await repo.setEntry(next);
    final old = replaced?.photoPath ?? before?.photoPath;
    if (old != null && old != next?.photoPath) {
      await _deleteIfUnreferenced(old);
    }
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
    final Entry? before;
    final Entry? replaced;
    try {
      before = await _existing(h, day);
      replaced = await repo.setEntry(
        photoEntry(h, day, name, _now(), existing: before),
      );
    } catch (_) {
      await photos.delete(name);
      rethrow;
    }
    final old = replaced?.photoPath ?? before?.photoPath;
    if (old != null && old != name) await _deleteIfUnreferenced(old);
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
  Future<void> archive(Habit h, DayKey today) async {
    if (h.isArchived) return;
    // A phone date before the start day (a flight west, a clock set back) must
    // not store an end the habit's own start rules out.
    final first = h.createdDay.addDays(-1);
    final last = today.addDays(-1);
    await repo.archive(h.id, last < first ? first : last);
  }

  Future<Habit> startAgain(Habit archived, DayKey today) =>
      repo.startAgain(archived, newId: _newId(), today: today);

  Future<DeletedHabit> deleteHabit(String id) async {
    final gone = await repo.deleteHabit(id);
    _undoable.add(gone);
    return gone;
  }

  Future<void> undoDelete(DeletedHabit gone) async {
    await repo.restoreHabit(gone);
    _undoable.remove(gone);
  }

  /// Call once the undo window has passed: only then are the photo files removed.
  Future<void> finishDelete(DeletedHabit gone) async {
    _undoable.remove(gone);
    final inUse = await _photosInUse();
    if (inUse != null) {
      for (final e in gone.entries) {
        final name = e.photoPath;
        if (name != null && !inUse.contains(name)) await photos.delete(name);
      }
    }
    await sweepOrphanPhotos();
  }

  /// Removes stored photos nothing refers to: those of a delete the app did
  /// not outlive the undo window of, or of data a restore replaced. A photo
  /// stored in the last hour may be for an entry still being saved, so it
  /// stays. Never throws: when anything is unclear, every photo stays.
  Future<void> sweepOrphanPhotos() async {
    try {
      final inUse = await _photosInUse();
      if (inUse == null) return;
      final before = _now().subtract(const Duration(hours: 1));
      for (final MapEntry(key: name, value: modified)
          in (await photos.listStored()).entries) {
        if (!inUse.contains(name) && modified.isBefore(before)) {
          await photos.delete(name);
        }
      }
    } catch (_) {
      // Left for the next sweep.
    }
  }

  Future<void> markSeen(DayKey day) => repo.markSeen(day);
}
