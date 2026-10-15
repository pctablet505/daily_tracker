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
      await act.slip(s, mon, note: 'party');
      expect((await entryOn('s', mon))?.note, 'party');
      await act.slip(s, mon);
      expect(await entryOn('s', mon), isNull);
      final a = await repo.addHabit(habit('a'));
      await act.skip(a, tue);
      expect((await entryOn('a', tue))?.state, EntryState.skipped);
      await act.skip(a, tue);
      expect(await entryOn('a', tue), isNull);
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

    test('archiving ends the habit yesterday, and is a no-op if already archived', () async {
      final h = await repo.addHabit(habit('a', created: mon));
      await act.archive(h, sun);
      final back = (await repo.habits()).single;
      expect(back.endDay, sat);
      expect(back.isActiveOn(sun), isFalse);
      expect(back.isActiveOn(sat), isTrue);
      await act.archive(back, sun.addDays(5));
      expect((await repo.habits()).single.endDay, sat);
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
          reason: 'finishDelete after undoDelete must not delete restored photo',
        );
        final again = await act.deleteHabit('p');
        await act.finishDelete(again);
        expect(photos.stored, isEmpty);
      },
    );

    test('start again makes a new habit beginning today', () async {
      final h = await repo.addHabit(habit('a', created: mon, end: tue));
      final fresh = await act.startAgain(h, sun);
      expect((fresh.id, fresh.createdDay, fresh.endDay), ('id0', sun, null));
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
