import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/logic/today_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

Ledger ledger(
  List<Habit> habits, [
  List<Entry> entries = const [],
  List<DayKey> seen = const [],
]) => Ledger(habits: habits, entries: entries, seenDays: seen);

List<String> ids(Iterable<HabitRow> rows) => [for (final r in rows) r.habit.id];

void main() {
  group('sections', () {
    test('a Do habit not yet done is to do; once done it moves to done', () {
      final a = habit('a');
      expect(ids(buildTodayView(ledger([a]), mon).toDo), ['a']);
      final v = buildTodayView(ledger([a], [entry('a', mon)]), mon);
      expect(v.toDo, isEmpty);
      expect(ids(v.finished), ['a']);
      expect(v.finished.single.kind, RowKind.done);
    });

    test(
      'a number habit short of its goal stays to do and carries its amount',
      () {
        final w = habit('w', logType: LogType.number, goal: 8);
        final v = buildTodayView(
          ledger([w], [entry('w', mon, EntryState.partial, 3)]),
          mon,
        );
        expect(ids(v.toDo), ['w']);
        expect(v.toDo.single.kind, RowKind.partial);
        expect(v.toDo.single.entry?.value, 3.0);
      },
    );

    test('a skipped day is listed with the finished ones', () {
      final v = buildTodayView(
        ledger([habit('a')], [entry('a', mon, EntryState.skipped)]),
        mon,
      );
      expect(v.finished.single.kind, RowKind.skipped);
      expect(v.toDo, isEmpty);
    });

    test('stay-clear habits have their own section and start on track', () {
      final v = buildTodayView(ledger([stayClear('s')], [], [mon]), mon);
      expect(ids(v.stayClear), ['s']);
      expect(v.stayClear.single.kind, RowKind.onTrack);
      expect(v.toDo, isEmpty);
      expect(v.finished, isEmpty);
    });

    test('a slip shows as slipped', () {
      final v = buildTodayView(ledger([stayClear('s')], [slip('s', mon)]), mon);
      expect(v.stayClear.single.kind, RowKind.slipped);
    });

    test('an avoid habit in confirm mode is listed like a Do habit', () {
      final c = habit('c', kind: HabitKind.avoid, avoidMode: AvoidMode.confirm);
      final v = buildTodayView(ledger([c]), mon);
      expect(ids(v.toDo), ['c']);
      expect(v.stayClear, isEmpty);
    });
  });

  group('what appears on a day', () {
    test('only habits scheduled for that weekday', () {
      final a = habit('a', mask: daysOf([1]));
      expect(ids(buildTodayView(ledger([a]), mon).toDo), ['a']);
      expect(buildTodayView(ledger([a]), tue).isEmpty, isTrue);
    });

    test(
      'a habit done on a day it was not scheduled still appears, as done',
      () {
        final a = habit('a', mask: daysOf([1]));
        final v = buildTodayView(ledger([a], [entry('a', tue)]), tue);
        expect(ids(v.finished), ['a']);
      },
    );

    test('not before it was created and not after it ended', () {
      final a = habit('a', created: wed, end: thu);
      expect(buildTodayView(ledger([a]), tue).isEmpty, isTrue);
      expect(buildTodayView(ledger([a]), wed).isEmpty, isFalse);
      expect(buildTodayView(ledger([a]), thu).isEmpty, isFalse);
      expect(buildTodayView(ledger([a]), fri).isEmpty, isTrue);
    });

    test('a stay-clear habit ignores the weekday mask', () {
      final s = habit('s', kind: HabitKind.avoid, mask: daysOf([1]));
      expect(ids(buildTodayView(ledger([s]), sat).stayClear), ['s']);
    });
  });

  group('order', () {
    test('by part of the day, then by position in the list', () {
      final hs = [
        habit('late').copyWith(dayPart: DayPart.evening, sortOrder: 0),
        habit('any').copyWith(dayPart: DayPart.anytime, sortOrder: 1),
        habit('am2').copyWith(dayPart: DayPart.morning, sortOrder: 3),
        habit('am1').copyWith(dayPart: DayPart.morning, sortOrder: 2),
        habit('pm').copyWith(dayPart: DayPart.afternoon, sortOrder: 4),
      ];
      expect(ids(buildTodayView(ledger(hs), mon).toDo), [
        'am1',
        'am2',
        'pm',
        'late',
        'any',
      ]);
    });
  });

  group('the day summary', () {
    test('counts the whole day, whatever the search shows', () {
      final hs = [habit('a'), habit('b')];
      final l = ledger(hs, [entry('a', mon)]);
      final v = buildTodayView(l, mon, query: 'Habit b');
      expect((v.summary.done, v.summary.planned), (1, 2));
      expect(ids(v.toDo), ['b']);
      expect(v.finished, isEmpty);
    });
  });

  group('search', () {
    final hs = [
      Habit(id: 'a', name: 'Morning run', createdDay: mon, area: 'Health'),
      Habit(
        id: 'b',
        name: 'Read',
        createdDay: mon,
        description: 'Fiction before bed',
      ),
      Habit(id: 'c', name: 'Journal', createdDay: mon),
    ];

    test(
      'matches name, description or area, ignoring case and surrounding space',
      () {
        final l = ledger(hs);
        expect(ids(buildTodayView(l, mon, query: ' RUN ').toDo), ['a']);
        expect(ids(buildTodayView(l, mon, query: 'fiction').toDo), ['b']);
        expect(ids(buildTodayView(l, mon, query: 'health').toDo), ['a']);
        expect(buildTodayView(l, mon, query: 'zzz').toDo, isEmpty);
      },
    );

    test('an empty query shows everything', () {
      expect(buildTodayView(ledger(hs), mon, query: '  ').toDo.length, 3);
    });

    test(
      'tells search with no match apart from a day with nothing planned',
      () {
        final v = buildTodayView(ledger(hs), mon, query: 'zzz');
        expect((v.isEmpty, v.hasAnyHabit), (true, true));
        final none = buildTodayView(ledger([]), mon);
        expect((none.isEmpty, none.hasAnyHabit), (true, false));
      },
    );
  });

  group('streak on each row', () {
    test('is the habit streak as of that day', () {
      final a = habit('a');
      final l = ledger(
        [a],
        [entry('a', mon), entry('a', tue), entry('a', wed)],
      );
      expect(buildTodayView(l, wed).finished.single.streak, 3);
      expect(buildTodayView(l, thu).toDo.single.streak, 3); // today still open
    });

    test('a stay-clear row counts days since the last slip', () {
      final s = stayClear('s');
      final l = ledger([s], [slip('s', tue)], [mon, tue, wed, thu]);
      expect(buildTodayView(l, thu).stayClear.single.streak, 2);
    });
  });

  group('what a row remembers', () {
    test('a number habit knows the last amount from an earlier day', () {
      final w = habit('w', logType: LogType.number);
      final l = ledger(
        [w],
        [
          entry('w', mon, EntryState.done, 75.9),
          entry('w', tue, EntryState.done, 75.5),
        ],
      );
      expect(buildTodayView(l, wed).toDo.single.lastValue, 75.5);
      expect(
        buildTodayView(l, tue).finished.single.lastValue,
        75.9,
        reason: 'today is not "last"',
      );
      expect(buildTodayView(l, mon).finished.single.lastValue, isNull);
    });

    test('a photo habit counts its photos up to the day shown', () {
      final p = habit('p', logType: LogType.photo);
      final l = ledger(
        [p],
        [
          Entry(
            habitId: 'p',
            day: mon,
            state: EntryState.done,
            photoPath: 'a.jpg',
            loggedAt: DateTime.utc(2026),
          ),
          Entry(
            habitId: 'p',
            day: wed,
            state: EntryState.done,
            photoPath: 'b.jpg',
            loggedAt: DateTime.utc(2026),
          ),
          Entry(
            habitId: 'p',
            day: thu,
            state: EntryState.done,
            loggedAt: DateTime.utc(2026),
          ), // no photo
        ],
      );
      expect(buildTodayView(l, wed).finished.single.photoCount, 2);
      expect(buildTodayView(l, tue).toDo.single.photoCount, 1);
      expect(buildTodayView(l, fri).toDo.single.photoCount, 2);
    });
  });
}
