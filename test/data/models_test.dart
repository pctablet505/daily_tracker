import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('Habit', () {
    final full = Habit(
      id: 'h1',
      name: 'Drink water',
      description: 'Glasses through the day',
      kind: HabitKind.build,
      logType: LogType.number,
      unit: 'glasses',
      goal: 8,
      daysMask: daysOf([1, 2, 3, 4, 5]),
      dayPart: DayPart.morning,
      reminderMinutes: 7 * 60 + 30,
      area: 'Health',
      avoidMode: AvoidMode.track,
      sortOrder: 3,
      createdDay: mon,
      endDay: fri,
    );

    test('survives a map round trip with every field', () {
      expect(Habit.fromMap(full.toMap()), full);
    });

    test('survives a round trip with only the required fields', () {
      final min = Habit(id: 'h2', name: 'Read', createdDay: mon);
      expect(Habit.fromMap(min.toMap()), min);
      expect(min.isArchived, isFalse);
      expect(min.daysMask, Habit.everyDay);
    });

    test('numbers that arrive as ints or doubles read the same', () {
      final m = full.toMap()
        ..['goal'] = 8
        ..['daysMask'] = 31.0;
      final h = Habit.fromMap(m);
      expect((h.goal, h.daysMask), (8.0, 31));
    });

    test('runsOn follows bit 0 = Monday ... bit 6 = Sunday', () {
      final h = Habit(
        id: 'x',
        name: 'x',
        createdDay: mon,
        daysMask: daysOf([1, 7]),
      );
      expect(
        [for (var d = 1; d <= 7; d++) h.runsOn(d)],
        [true, false, false, false, false, false, true],
      );
      expect(Habit.weekdaysOnly, daysOf([1, 2, 3, 4, 5]));
    });

    test('tracksSlips is true only for an avoid habit in track mode', () {
      Habit mk(HabitKind k, AvoidMode m) =>
          Habit(id: 'x', name: 'x', createdDay: mon, kind: k, avoidMode: m);
      expect(mk(HabitKind.avoid, AvoidMode.track).tracksSlips, isTrue);
      expect(mk(HabitKind.avoid, AvoidMode.confirm).tracksSlips, isFalse);
      expect(mk(HabitKind.build, AvoidMode.track).tracksSlips, isFalse);
    });

    test(
      'copyWith changes one field, can clear an optional one, and keeps the id',
      () {
        final c = full.copyWith(
          name: 'Water',
          reminderMinutes: () => null,
          endDay: () => null,
        );
        expect(c.id, 'h1');
        expect(c.name, 'Water');
        expect(c.reminderMinutes, isNull);
        expect(c.isArchived, isFalse);
        expect(c.unit, 'glasses');
        expect(c.copyWith(unit: () => 'cups').unit, 'cups');
      },
    );

    test(
      'equal habits are equal and share a hash; any differing field breaks it',
      () {
        expect(full, Habit.fromMap(full.toMap()));
        expect(full.hashCode, Habit.fromMap(full.toMap()).hashCode);
        expect(full == full.copyWith(sortOrder: 4), isFalse);
        expect(full == full.copyWith(area: () => 'Mind'), isFalse);
      },
    );

    for (final c in <(String, Map<String, Object?>)>[
      ('no id', {'name': 'x', 'createdDay': '2026-10-05'}),
      ('empty id', {'id': '', 'name': 'x', 'createdDay': '2026-10-05'}),
      ('no name', {'id': 'a', 'createdDay': '2026-10-05'}),
      ('blank name', {'id': 'a', 'name': '  ', 'createdDay': '2026-10-05'}),
      ('no createdDay', {'id': 'a', 'name': 'x'}),
      ('bad createdDay', {'id': 'a', 'name': 'x', 'createdDay': '2026-02-30'}),
      (
        'bad endDay',
        {'id': 'a', 'name': 'x', 'createdDay': '2026-10-05', 'endDay': 'soon'},
      ),
      (
        'unknown kind',
        {'id': 'a', 'name': 'x', 'createdDay': '2026-10-05', 'kind': 'maybe'},
      ),
      (
        'unknown logType',
        {
          'id': 'a',
          'name': 'x',
          'createdDay': '2026-10-05',
          'logType': 'video',
        },
      ),
    ]) {
      test('is rejected when it has ${c.$1}', () {
        expect(() => Habit.fromMap(c.$2), throwsFormatException);
      });
    }
  });

  group('Entry', () {
    final e = Entry(
      habitId: 'h1',
      day: wed,
      state: EntryState.partial,
      value: 3.5,
      note: 'felt ok',
      photoPath: 'a.jpg',
      loggedAt: DateTime.utc(2026, 10, 7, 9, 30),
    );

    test('survives a map round trip', () {
      expect(Entry.fromMap(e.toMap()), e);
      expect(e.toMap()['loggedAt'], '2026-10-07T09:30:00.000Z');
    });

    test('a local time is stored as UTC and reads back as the same moment', () {
      final local = Entry(
        habitId: 'h',
        day: wed,
        state: EntryState.done,
        loggedAt: DateTime(2026, 10, 7, 21, 15),
      );
      expect(
        Entry.fromMap(local.toMap()).loggedAt.isAtSameMomentAs(local.loggedAt),
        isTrue,
      );
    });

    test('copyWith can set and clear the value, note and photo', () {
      final c = e.copyWith(
        state: EntryState.done,
        value: () => null,
        photoPath: () => null,
      );
      expect(
        (c.state, c.value, c.photoPath, c.note),
        (EntryState.done, null, null, 'felt ok'),
      );
    });

    test(
      'a missing loggedAt reads as the epoch rather than failing the import',
      () {
        final m = e.toMap()..remove('loggedAt');
        expect(Entry.fromMap(m).loggedAt.millisecondsSinceEpoch, 0);
      },
    );

    for (final c in <(String, Map<String, Object?>)>[
      ('no habitId', {'day': '2026-10-07', 'state': 'done'}),
      ('no day', {'habitId': 'h', 'state': 'done'}),
      ('bad day', {'habitId': 'h', 'day': '07/10/2026', 'state': 'done'}),
      (
        'unknown state',
        {'habitId': 'h', 'day': '2026-10-07', 'state': 'finished'},
      ),
    ]) {
      test('is rejected when it has ${c.$1}', () {
        expect(() => Entry.fromMap(c.$2), throwsFormatException);
      });
    }

    test('a missing state reads as done', () {
      expect(
        Entry.fromMap({'habitId': 'h', 'day': '2026-10-07'}).state,
        EntryState.done,
      );
    });
  });

  test('DayKey in a map is the plain text form', () {
    expect(
      Habit(
        id: 'a',
        name: 'x',
        createdDay: const DayKey(2026, 1, 5),
      ).toMap()['createdDay'],
      '2026-01-05',
    );
  });
}
