import 'package:sqflite/sqflite.dart';

import '../core/day_key.dart';
import 'models.dart';

/// A habit that was just deleted, with everything needed to undo it.
final class DeletedHabit {
  const DeletedHabit(this.habit, this.entries);
  final Habit habit;
  final List<Entry> entries;
}

/// Everything the app stores. Backups are written from and restored into this.
final class Snapshot {
  const Snapshot({required this.habits, required this.entries, required this.seenDays});
  final List<Habit> habits;
  final List<Entry> entries;
  final Set<DayKey> seenDays;

  /// Throws [FormatException] when the data could not be stored consistently.
  void validate() {
    final ids = <String>{};
    for (final h in habits) {
      if (!ids.add(h.id)) throw FormatException('Two habits share the id', h.id);
    }
    final seen = <(String, DayKey)>{};
    for (final e in entries) {
      if (!ids.contains(e.habitId)) {
        throw FormatException('An entry belongs to a habit that is not in the data', e.habitId);
      }
      if (!seen.add((e.habitId, e.day))) {
        throw FormatException('Two entries for the same habit and day', '${e.habitId} ${e.day}');
      }
    }
  }
}

/// Reads and writes habits, entries and seen days. [onChanged] runs after
/// every write that changed something, so screens can refresh.
final class HabitRepository {
  HabitRepository(this._db, {this._onChanged});

  final Database _db;
  final void Function()? _onChanged;

  void _changed() => _onChanged?.call();

  // Habits

  /// Every habit, archived ones included, in display order.
  Future<List<Habit>> habits() async {
    final rows = await _db.query('habits', orderBy: 'sortOrder, createdDay, id');
    return [for (final r in rows) Habit.fromMap(r)];
  }

  /// Stores [habit] at the end of the list and returns it as stored.
  Future<Habit> addHabit(Habit habit) async {
    final stored = await _db.transaction((txn) async {
      final next = Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM habits')) ??
          0;
      final h = habit.copyWith(sortOrder: next);
      await txn.insert('habits', h.toMap());
      return h;
    });
    _changed();
    return stored;
  }

  Future<void> updateHabit(Habit habit) async {
    final n = await _db.update('habits', habit.toMap(), where: 'id = ?', whereArgs: [habit.id]);
    if (n == 0) throw StateError('No habit with id ${habit.id}');
    _changed();
  }

  /// Sets the order to the position in [ids]; pass every habit.
  Future<void> reorder(List<String> ids) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < ids.length; i++) {
        batch.update('habits', {'sortOrder': i}, where: 'id = ?', whereArgs: [ids[i]]);
      }
      await batch.commit(noResult: true);
    });
    _changed();
  }

  /// Ends the habit on [lastDay] (inclusive). Its entries stay.
  Future<void> archive(String id, DayKey lastDay) async {
    final n = await _db.update('habits', {'endDay': lastDay.toString()}, where: 'id = ?', whereArgs: [id]);
    if (n == 0) throw StateError('No habit with id $id');
    _changed();
  }

  /// Makes a fresh habit with [archived]'s settings, beginning [today]. The old
  /// habit and its history stay as they were, so past rates do not change.
  Future<Habit> startAgain(Habit archived, {required String newId, required DayKey today}) {
    return addHabit(Habit(
      id: newId,
      name: archived.name,
      description: archived.description,
      kind: archived.kind,
      logType: archived.logType,
      unit: archived.unit,
      goal: archived.goal,
      daysMask: archived.daysMask,
      dayPart: archived.dayPart,
      reminderMinutes: archived.reminderMinutes,
      area: archived.area,
      avoidMode: archived.avoidMode,
      createdDay: today,
    ));
  }

  /// Removes the habit and its entries and returns them for an undo.
  Future<DeletedHabit> deleteHabit(String id) async {
    final gone = await _db.transaction((txn) async {
      final rows = await txn.query('habits', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('No habit with id $id');
      final entries = await txn.query('entries', where: 'habitId = ?', whereArgs: [id], orderBy: 'day');
      await txn.delete('habits', where: 'id = ?', whereArgs: [id]);
      return DeletedHabit(Habit.fromMap(rows.single), [for (final r in entries) Entry.fromMap(r)]);
    });
    _changed();
    return gone;
  }

  Future<void> restoreHabit(DeletedHabit gone) async {
    await _db.transaction((txn) async {
      await txn.insert('habits', gone.habit.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      for (final e in gone.entries) {
        await txn.insert('entries', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _changed();
  }

  // Entries

  /// Entries in day order, optionally limited to [from]..[to] (inclusive).
  Future<List<Entry>> entries({DayKey? from, DayKey? to, String? habitId}) async {
    final where = <String>[];
    final args = <Object>[];
    if (from != null) {
      where.add('day >= ?');
      args.add(from.toString());
    }
    if (to != null) {
      where.add('day <= ?');
      args.add(to.toString());
    }
    if (habitId != null) {
      where.add('habitId = ?');
      args.add(habitId);
    }
    final rows = await _db.query(
      'entries',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'day, habitId',
    );
    return [for (final r in rows) Entry.fromMap(r)];
  }

  /// Stores [entry], replacing any for the same habit and day, and returns the
  /// one it replaced (so a photo it pointed at can be cleaned up).
  Future<Entry?> setEntry(Entry entry) async {
    final replaced = await _db.transaction((txn) async {
      final old = await txn.query('entries',
          where: 'habitId = ? AND day = ?', whereArgs: [entry.habitId, entry.day.toString()]);
      await txn.insert('entries', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      return old.isEmpty ? null : Entry.fromMap(old.single);
    });
    _changed();
    return replaced;
  }

  /// Removes the entry and returns it, or null when there was none.
  Future<Entry?> clearEntry(String habitId, DayKey day) async {
    final removed = await _db.transaction((txn) async {
      final old = await txn.query('entries', where: 'habitId = ? AND day = ?', whereArgs: [habitId, day.toString()]);
      if (old.isEmpty) return null;
      await txn.delete('entries', where: 'habitId = ? AND day = ?', whereArgs: [habitId, day.toString()]);
      return Entry.fromMap(old.single);
    });
    if (removed != null) _changed();
    return removed;
  }

  // Seen days

  Future<Set<DayKey>> seenDays() async {
    final rows = await _db.query('seen_days');
    return {for (final r in rows) DayKey.parse(r['day']! as String)};
  }

  /// Records that the app was opened (or a check-in answered) on [day].
  /// Returns true when the day was not recorded yet.
  Future<bool> markSeen(DayKey day) async {
    final id = await _db.insert('seen_days', {'day': day.toString()}, conflictAlgorithm: ConflictAlgorithm.ignore);
    final isNew = id != 0;
    if (isNew) _changed();
    return isNew;
  }

  // Whole-database

  Future<Snapshot> snapshot() async => Snapshot(
        habits: await habits(),
        entries: await entries(),
        seenDays: await seenDays(),
      );

  /// Replaces everything with [snapshot] in one transaction. If the data is
  /// inconsistent nothing is touched and a [FormatException] is thrown.
  Future<void> replaceAll(Snapshot snapshot) async {
    snapshot.validate();
    await _db.transaction((txn) async {
      await txn.delete('entries');
      await txn.delete('habits');
      await txn.delete('seen_days');
      for (final h in snapshot.habits) {
        await txn.insert('habits', h.toMap());
      }
      for (final e in snapshot.entries) {
        await txn.insert('entries', e.toMap());
      }
      for (final d in snapshot.seenDays) {
        await txn.insert('seen_days', {'day': d.toString()});
      }
    });
    _changed();
  }
}
