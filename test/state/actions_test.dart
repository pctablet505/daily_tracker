import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/state/actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

final class FakePhotos implements PhotoStore {
  final stored = <String>{};
  final deleted = <String>[];
  var _n = 0;

  @override
  Future<String> importFile(String sourcePath) async {
    final name = 'ph${_n++}.jpg';
    stored.add(name);
    return name;
  }

  @override
  File fileFor(String name) => File('/nope/$name');

  @override
  bool exists(String name) => stored.contains(name);

  @override
  Future<void> delete(String name) async {
    stored.remove(name);
    deleted.add(name);
  }

  /// When each stored photo was written; a photo not named here is a day old.
  final modified = <String, DateTime>{};

  @override
  Future<Map<String, DateTime>> listStored() async => {
    for (final name in stored)
      name: modified[name] ?? DateTime.utc(2026, 10, 10, 9),
  };
}

void main() {
  sqfliteFfiInit();
  late HabitRepository repo;
  late FakePhotos photos;
  late HabitActions act;
  final t0 = DateTime.utc(2026, 10, 11, 9);
  var ids = 0;

  Future<Entry?> entryOn(String id, DayKey d) async =>
      (await repo.entries(habitId: id, from: d, to: d)).firstOrNull;

  setUp(() async {
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    repo = HabitRepository(db);
    photos = FakePhotos();
    ids = 0;
    act = HabitActions(
      repo: repo,
      photos: photos,
      now: () => t0,
      newId: () => 'id${ids++}',
    );
  });

  group('logging', () {
    test('a tick marks the day done and a second tick takes it off', () async {
      final h = await repo.addHabit(habit('a'));
      await act.tick(h, mon);
      expect((await entryOn('a', mon))?.state, EntryState.done);
      expect((await entryOn('a', mon))?.loggedAt, t0);
      await act.tick(h, mon);
      expect(await entryOn('a', mon), isNull);
    });

    test('logging a past day does not touch today', () async {
      final h = await repo.addHabit(habit('a'));
      await act.tick(h, mon);
      expect(await entryOn('a', sun), isNull);
    });

    test(
      'a number short of the goal is partial, then done at the goal',
      () async {
        final h = await repo.addHabit(
          habit('w', logType: LogType.number, goal: 8),
        );
        await act.logNumber(h, mon, 3);
        expect((await entryOn('w', mon))?.state, EntryState.partial);
        await act.logNumber(h, mon, 8);
        expect((await entryOn('w', mon))?.state, EntryState.done);
        await act.logNumber(h, mon, 0);
        expect(await entryOn('w', mon), isNull);
      },
    );

    test('a note is stored; blank clears', () async {
      final h = await repo.addHabit(habit('j', logType: LogType.note));
      await act.logNote(h, mon, ' hello ');
      expect((await entryOn('j', mon))?.note, 'hello');
      await act.logNote(h, mon, ' ');
      expect(await entryOn('j', mon), isNull);
    });

    test('a slip, then taking it back; a skip, then taking it back', () async {
      final s = await repo.addHabit(stayClear('s'));
      await act.slip(s, mon);
      expect((await entryOn('s', mon))?.state, EntryState.slipped);
      await act.slip(s, mon);
      expect(await entryOn('s', mon), isNull);
      // A note is never deleted by a tap: the day goes back on track with it.
      await act.slip(s, tue, note: 'party');
      expect((await entryOn('s', tue))?.note, 'party');
      await act.slip(s, tue);
      final back = await entryOn('s', tue);
      expect((back?.state, back?.note), (EntryState.done, 'party'));
      final a = await repo.addHabit(habit('a'));
      await act.skip(a, tue);
      expect((await entryOn('a', tue))?.state, EntryState.skipped);
      await act.skip(a, tue);
      expect(await entryOn('a', tue), isNull);
    });

    test('taking back a slip on a day that holds a photo keeps the photo and its file', () async {
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await act.logPhoto(h, mon, '/c/1.jpg');
      // Edited to stay-clear: the photo day stays.
      final s = h.copyWith(
        kind: HabitKind.avoid,
        avoidMode: AvoidMode.track,
        logType: LogType.tick,
      );
      await act.updateHabit(s);
      await act.slip(s, mon);
      await act.slip(s, mon); // the toast's Undo, or "Undo slip"
      final back = await entryOn('p', mon);
      expect((back?.state, back?.photoPath), (EntryState.done, 'ph0.jpg'));
      expect(photos.stored, {'ph0.jpg'});
    });

    test('"I stayed clear" puts that one habit on track for the day, and nothing else', () async {
      final sugar = await repo.addHabit(stayClear('sugar'));
      await repo.addHabit(stayClear('smoke'));
      await act.stayedClear(sugar, wed);
      final e = await entryOn('sugar', wed);
      expect((e?.state, e?.loggedAt), (EntryState.done, t0));
      expect(await entryOn('smoke', wed), isNull);
      expect(await repo.seenDays(), isEmpty);
    });

    test('clear removes whatever was logged', () async {
      final h = await repo.addHabit(habit('a'));
      await act.tick(h, mon);
      await act.clear(h, mon);
      expect(await entryOn('a', mon), isNull);
    });
  });

  group('photos', () {
    test(
      'a photo is copied into the store and the entry keeps its name',
      () async {
        final h = await repo.addHabit(habit('p', logType: LogType.photo));
        await act.logPhoto(h, mon, '/cache/scaled_1.jpg');
        expect((await entryOn('p', mon))?.photoPath, 'ph0.jpg');
        expect(photos.stored, {'ph0.jpg'});
      },
    );

    test('replacing the photo removes the old file', () async {
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await act.logPhoto(h, mon, '/c/1.jpg');
      await act.logPhoto(h, mon, '/c/2.jpg');
      expect(photos.stored, {'ph1.jpg'});
      expect(photos.deleted, ['ph0.jpg']);
    });

    test('clearing the day removes its photo file', () async {
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await act.logPhoto(h, mon, '/c/1.jpg');
      await act.clear(h, mon);
      expect(photos.stored, isEmpty);
    });

    test('a note added to a photo day keeps the photo file', () async {
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await act.logPhoto(h, mon, '/c/1.jpg');
      await act.logNote(h, mon, 'sunrise');
      expect(photos.stored, {'ph0.jpg'});
      expect((await entryOn('p', mon))?.photoPath, 'ph0.jpg');
    });

    test(
      'if the entry cannot be saved the copied photo is removed again',
      () async {
        final ghost = habit(
          'ghost',
          logType: LogType.photo,
        ); // never added: the entry is refused
        await expectLater(
          act.logPhoto(ghost, mon, '/c/1.jpg'),
          throwsA(anything),
        );
        expect(photos.stored, isEmpty);
      },
    );
  });

  group('habits', () {
    test(
      'adding gives the habit an id from the generator when it has none',
      () async {
        final h = await act.addHabit(
          habit('x').copyWith(name: '  Walk '),
          today: sun,
        );
        expect(h.id, 'id0');
        expect(h.createdDay, sun);
        expect((await repo.habits()).single.name, 'Walk');
      },
    );

    test(
      'archiving ends the habit yesterday, and is a no-op if already archived',
      () async {
        final h = await repo.addHabit(habit('a', created: mon));
        await act.archive(h, sun);
        final back = (await repo.habits()).single;
        expect(back.endDay, sat);
        expect(back.isActiveOn(sun), isFalse);
        expect(back.isActiveOn(sat), isTrue);
        await act.archive(back, sun.addDays(5));
        expect((await repo.habits()).single.endDay, sat);
      },
    );

    test('archiving while the phone date is before the start day stores an end every reader accepts', () async {
      final db = await openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      addTearDown(db.close);
      final r = HabitRepository(db);
      final a = HabitActions(
        repo: r,
        photos: photos,
        now: () => t0,
        newId: () => 'x',
      );
      // Made on Thursday, archived with the phone's clock set back to Monday.
      await a.archive(await r.addHabit(habit('a', created: thu)), mon);
      // Made and archived on its first day: off the lists from that day on.
      await a.archive(await r.addHabit(habit('b', created: sun)), sun);
      final stored = [
        for (final row in await db.query('habits', orderBy: 'id'))
          Habit.fromMap(row),
      ];
      expect(stored.map((h) => h.endDay), [wed, sat]);
      expect(
        stored.any((h) => h.isActiveOn(thu) || h.isActiveOn(sun)),
        isFalse,
      );
    });

    test(
      'delete can be undone, and only finishing it removes the photos',
      () async {
        final h = await repo.addHabit(habit('p', logType: LogType.photo));
        await act.logPhoto(h, mon, '/c/1.jpg');
        final gone = await act.deleteHabit('p');
        expect(photos.stored, {
          'ph0.jpg',
        }, reason: 'photo kept during the undo window');
        await act.undoDelete(gone);
        expect((await entryOn('p', mon))?.photoPath, 'ph0.jpg');
        await act.finishDelete(gone);
        expect(
          photos.stored,
          {'ph0.jpg'},
          reason:
              'finishDelete after undoDelete must not delete restored photo',
        );
        final again = await act.deleteHabit('p');
        await act.finishDelete(again);
        expect(photos.stored, isEmpty);
      },
    );

    test('finishing a delete removes a photo taken in the last hour, which the sweep keeps', () async {
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await act.logPhoto(h, mon, '/c/1.jpg');
      photos.modified['ph0.jpg'] = t0.subtract(const Duration(minutes: 5));
      await act.finishDelete(await act.deleteHabit('p'));
      expect(photos.stored, isEmpty);
    });

    test(
      'adding several gives each an id and stores them together, in order',
      () async {
        final added = await act.addHabits([
          habit('x').copyWith(name: ' Walk '),
          habit('y').copyWith(name: 'Read'),
        ], today: sun);
        expect(added.map((h) => (h.id, h.createdDay)), [
          ('id0', sun),
          ('id1', sun),
        ]);
        expect((await repo.habits()).map((h) => h.name), ['Walk', 'Read']);
      },
    );

    test('start again makes a new habit beginning today', () async {
      final h = await repo.addHabit(habit('a', created: mon, end: tue));
      final fresh = await act.startAgain(h, sun);
      expect((fresh.id, fresh.createdDay, fresh.endDay), ('id0', sun, null));
    });
  });

  group('photos nothing refers to', () {
    HabitActions keeping(Set<String>? bySafetyCopies) => HabitActions(
      repo: repo,
      photos: photos,
      now: () => t0,
      newId: () => 'x',
      keptBySafetyCopies: () async => bySafetyCopies,
    );

    test(
      'the photos of a delete the app did not outlive go at the next sweep',
      () async {
        final h = await repo.addHabit(habit('p', logType: LogType.photo));
        await act.logPhoto(h, mon, '/c/1.jpg');
        await act.deleteHabit('p');
        // The app is stopped in the undo window, so finishDelete never runs.
        await keeping(const {}).sweepOrphanPhotos();
        expect(photos.stored, isEmpty);
      },
    );

    test('the sweep keeps photos an entry refers to and photos stored in the last hour', () async {
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await act.logPhoto(h, mon, '/c/1.jpg');
      photos.stored.addAll({'stray.jpg', 'fresh.jpg'});
      photos.modified['stray.jpg'] = t0.subtract(const Duration(minutes: 61));
      photos.modified['fresh.jpg'] = t0.subtract(const Duration(minutes: 59));
      await act.sweepOrphanPhotos();
      expect(photos.stored, {'ph0.jpg', 'fresh.jpg'});
    });

    test('the sweep after one delete keeps the photos of another delete that can still be undone', () async {
      final a = await repo.addHabit(habit('a', logType: LogType.photo));
      final b = await repo.addHabit(habit('b', logType: LogType.photo));
      await act.logPhoto(a, mon, '/c/1.jpg');
      await act.logPhoto(b, mon, '/c/2.jpg');
      photos.stored.add('stray.jpg');
      final goneA = await act.deleteHabit('a');
      final goneB = await act.deleteHabit('b');
      // Deleting b closes a's undo window.
      await act.finishDelete(goneA);
      expect(photos.stored, {'ph1.jpg'});
      await act.undoDelete(goneB);
      await act.sweepOrphanPhotos();
      expect(photos.stored, {'ph1.jpg'});
    });

    test('replacing or clearing a photo keeps the old file while a safety copy refers to it', () async {
      final kept = keeping({'ph0.jpg'});
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await kept.logPhoto(h, mon, '/c/1.jpg');
      await kept.logPhoto(h, mon, '/c/2.jpg');
      expect(photos.stored, {'ph0.jpg', 'ph1.jpg'});
      await kept.clear(h, mon);
      expect(photos.stored, {'ph0.jpg'});
    });

    test(
      'finishing a delete keeps the photos a safety copy refers to',
      () async {
        final kept = keeping({'ph0.jpg'});
        final h = await repo.addHabit(habit('p', logType: LogType.photo));
        await kept.logPhoto(h, mon, '/c/1.jpg');
        await kept.logPhoto(h, tue, '/c/2.jpg');
        await kept.finishDelete(await kept.deleteHabit('p'));
        expect(photos.stored, {'ph0.jpg'});
      },
    );

    test('when a safety copy cannot be read, no photo is removed', () async {
      final unsure = keeping(null);
      final h = await repo.addHabit(habit('p', logType: LogType.photo));
      await unsure.logPhoto(h, mon, '/c/1.jpg');
      await unsure.logPhoto(h, mon, '/c/2.jpg');
      photos.stored.add('stray.jpg');
      await unsure.finishDelete(await unsure.deleteHabit('p'));
      await unsure.sweepOrphanPhotos();
      expect(photos.stored, {'ph0.jpg', 'ph1.jpg', 'stray.jpg'});
    });

    test('the sweep removes nothing, and does not throw, when the entries cannot be read', () async {
      final db = await openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      final a = HabitActions(
        repo: HabitRepository(db),
        photos: photos,
        now: () => t0,
        newId: () => 'x',
      );
      photos.stored.add('stray.jpg');
      await db.close();
      await a.sweepOrphanPhotos();
      expect(photos.stored, {'stray.jpg'});
    });
  });

  group('order', () {
    test('the named habits come first in the given order, the rest keep their order after', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await repo.addHabit(habit(id));
      }
      await act.reorder(['c', 'a'], ['a', 'b', 'c', 'd']);
      expect((await repo.habits()).map((h) => h.id), ['c', 'a', 'b', 'd']);
    });
  });

  group('seen days', () {
    test('opening the app marks the day once', () async {
      await act.markSeen(sun);
      await act.markSeen(sun);
      expect(await repo.seenDays(), {sun});
    });
  });
}
