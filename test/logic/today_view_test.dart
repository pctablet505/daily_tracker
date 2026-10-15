import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/logic/habit_detail.dart';
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

    test(
      'a tick taken off a day that holds a photo is to do again everywhere',
      () {
        final t = habit('t', mask: Habit.weekdaysOnly);
        final kept = Entry(
          habitId: 't',
          day: mon,
          state: EntryState.partial,
          photoPath: 'a.jpg',
          loggedAt: DateTime.utc(2026),
        );
        final l = ledger([t], [kept, entry('t', tue)], [mon, tue, wed]);
        final v = buildTodayView(l, mon);
        expect(ids(v.toDo), ['t']);
        expect(v.toDo.single.kind, RowKind.todo);
        expect((v.summary.done, v.summary.planned), (0, 1));
        final d = buildHabitDetail(l, t, wed);
        expect(
          d.recentDays.firstWhere((x) => x.day == mon).state,
          DotState.missed,
        );
        expect(d.totalDone, 1);
        expect(d.streak, const HabitStreak(current: 1, best: 1));
        expect(d.photos.single.photoPath, 'a.jpg');
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

    test('a skipped stay-clear day is listed with the finished ones', () {
      final v = buildTodayView(
        ledger([stayClear('s')], [entry('s', mon, EntryState.skipped)], [mon]),
        mon,
      );
      expect(v.stayClear, isEmpty);
      expect(v.finished.single.kind, RowKind.skipped);
    });

    test(
      'a stay-clear habit on a past day the app never saw is not checked',
      () {
        // Wednesday was never seen: the summary and the streak do not count it.
        final l = ledger([stayClear('s')], [], [mon, tue, thu, sun]);
        final row = buildTodayView(l, wed, today: sun).stayClear.single;
        expect(row.kind, RowKind.unchecked);
        // Today is still open, and a day that was seen counts as clean.
        final today = buildTodayView(ledger([stayClear('s')]), sun, today: sun);
        expect(today.stayClear.single.kind, RowKind.onTrack);
        expect(
          buildTodayView(l, thu, today: sun).stayClear.single.kind,
          RowKind.onTrack,
        );
      },
    );

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

    test(
      'not before it was created and not after it ended, even with an entry',
      () {
        final a = habit('a', created: wed, end: thu);
        expect(buildTodayView(ledger([a]), tue).isEmpty, isTrue);
        expect(buildTodayView(ledger([a]), wed).isEmpty, isFalse);
        expect(buildTodayView(ledger([a]), thu).isEmpty, isFalse);
        expect(
          buildTodayView(ledger([a], [entry('a', fri)]), fri).isEmpty,
          isTrue,
        );
      },
    );

    test('a slip left from before an edit to "Do this" agrees with the summary and the habit page', () {
      // Stay-clear until it was edited to a weekday Do habit; the edit keeps
      // the slipped rows of Friday and Saturday.
      final h = habit('h', mask: Habit.weekdaysOnly);
      final o = habit('o');
      final l = ledger(
        [h, o],
        [slip('h', fri), slip('h', sat), entry('o', fri), entry('o', sat)],
        [fri, sat],
      );
      final dots = {
        for (final d in buildHabitDetail(l, h, sat).recentDays) d.day: d.state,
      };

      final saturday = buildTodayView(l, sat);
      expect(ids(saturday.toDo), isEmpty);
      expect(ids(saturday.finished), ['o']);
      expect((saturday.summary.done, saturday.summary.planned), (1, 1));
      expect(dots[sat], DotState.none);

      final friday = buildTodayView(l, fri);
      expect(ids(friday.toDo), ['h']);
      expect(friday.toDo.single.kind, RowKind.todo);
      expect((friday.summary.done, friday.summary.planned), (1, 2));
      expect(dots[fri], DotState.missed);
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

    test('once every habit has ended there is nothing to track, not just nothing planned', () {
      final l = ledger([habit('a', end: wed), stayClear('s', end: wed)]);
      expect(buildTodayView(l, thu).hasAnyHabit, isFalse);
      expect(buildTodayView(l, wed).hasAnyHabit, isTrue);
    });
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

    test('a missed day looked back on from a later day shows no streak', () {
      final a = habit('a');
      final l = ledger(
        [a],
        [entry('a', mon), entry('a', tue), entry('a', wed)],
        [mon, tue, wed, thu, fri],
      );
      expect(buildTodayView(l, thu, today: fri).toDo.single.streak, 0);
      expect(buildTodayView(l, thu, today: thu).toDo.single.streak, 3);
    });

    test('a stay-clear row counts days since the last slip', () {
      final s = stayClear('s');
      final l = ledger([s], [slip('s', tue)], [mon, tue, wed, thu]);
      expect(buildTodayView(l, thu).stayClear.single.streak, 2);
    });
  });

  group('what a row remembers', () {
    test(
      'a number habit knows the last non-skipped amount from an earlier day',
      () {
        final w = habit('w', logType: LogType.number);
        final l = ledger(
          [w],
          [
            entry('w', mon, EntryState.done, 75.9),
            entry('w', tue, EntryState.done, 75.5),
            entry('w', wed, EntryState.skipped, 99.0),
          ],
        );
        expect(buildTodayView(l, thu).toDo.single.lastValue, 75.5);
        expect(
          buildTodayView(l, tue).finished.single.lastValue,
          75.9,
          reason: 'today is not "last"',
        );
        expect(buildTodayView(l, mon).finished.single.lastValue, isNull);
      },
    );

    test('a photo habit counts its non-skipped photos up to the day shown', () {
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
            state: EntryState.skipped,
            photoPath: 'skipped.jpg',
            loggedAt: DateTime.utc(2026),
          ),
          Entry(
            habitId: 'p',
            day: fri,
            state: EntryState.done,
            loggedAt: DateTime.utc(2026),
          ), // no photo
        ],
      );
      expect(buildTodayView(l, wed).finished.single.photoCount, 2);
      expect(buildTodayView(l, tue).toDo.single.photoCount, 1);
      expect(buildTodayView(l, fri).finished.single.photoCount, 2);
    });

    test(
      'a photo whose file is gone is not counted (a restore brings no photos)',
      () {
        final p = habit('p', logType: LogType.photo);
        Entry photo(DayKey d, String name) => Entry(
          habitId: 'p',
          day: d,
          state: EntryState.done,
          photoPath: name,
          loggedAt: DateTime.utc(2026),
        );
        final l = ledger(
          [p],
          [
            photo(mon, 'here.jpg'),
            photo(tue, 'gone.jpg'),
            photo(wed, 'also-gone.jpg'),
          ],
        );
        expect(
          buildTodayView(
            l,
            wed,
            photoExists: (name) => name == 'here.jpg',
          ).finished.single.photoCount,
          1,
        );
        expect(
          buildTodayView(
            l,
            wed,
            photoExists: (_) => false,
          ).finished.single.photoCount,
          0,
        );
        expect(
          buildTodayView(l, wed).finished.single.photoCount,
          3,
          reason: 'without a check every recorded photo counts, as before',
        );
      },
    );
  });
}
