import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/logic/logging.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 10, 11, 9);
  final tick = habit('t');
  final water = habit('w', logType: LogType.number, goal: 8);
  final steps = habit('n', logType: LogType.number); // number without a goal
  final s = stayClear('s');

  group('tapping a tick habit', () {
    test('marks it done', () {
      final e = tickEntry(tick, mon, null, now);
      expect((e?.state, e?.habitId, e?.day, e?.loggedAt), (EntryState.done, 't', mon, now));
    });

    test('taps off what was done', () {
      expect(tickEntry(tick, mon, entry('t', mon), now), isNull);
    });

    test('a skipped day becomes done', () {
      expect(tickEntry(tick, mon, entry('t', mon, EntryState.skipped), now)?.state, EntryState.done);
    });

    test('a slipped confirm-mode habit becomes done', () {
      final c = habit('c', kind: HabitKind.avoid, avoidMode: AvoidMode.confirm);
      expect(tickEntry(c, mon, entry('c', mon, EntryState.slipped), now)?.state, EntryState.done);
    });
  });

  group('logging a number', () {
    for (final c in <(Habit, double, EntryState?)>[
      (water, 3, EntryState.partial),
      (water, 8, EntryState.done),
      (water, 12, EntryState.done),
      (water, 0, null),
      (water, -1, null),
      (steps, 0.5, EntryState.done), // no goal: any positive amount counts
      (steps, 0, null),
    ]) {
      test('${c.$1.id} ${c.$2} -> ${c.$3?.name ?? 'cleared'}', () {
        final e = numberEntry(c.$1, mon, c.$2, now);
        expect(e?.state, c.$3);
        if (e != null) expect(e.value, c.$2);
      });
    }
  });

  group('logging a note', () {
    test('keeps the trimmed text and marks the day done', () {
      final e = noteEntry(habit('j', logType: LogType.note), mon, '  walked by the river \n', now);
      expect((e?.state, e?.note), (EntryState.done, 'walked by the river'));
    });

    test('blank text clears it', () {
      expect(noteEntry(habit('j', logType: LogType.note), mon, '  \n', now), isNull);
    });
  });

  group('logging a photo', () {
    test('stores the file name and marks the day done', () {
      final e = photoEntry(habit('p', logType: LogType.photo), mon, 'a1.jpg', now);
      expect((e.state, e.photoPath), (EntryState.done, 'a1.jpg'));
    });
  });

  group('stay-clear habits', () {
    test('a slip is logged, and tapping it again takes it back', () {
      final e = slipEntry(s, mon, null, now);
      expect(e?.state, EntryState.slipped);
      expect(slipEntry(s, mon, e, now), isNull);
    });

    test('a slip keeps a note about what happened', () {
      expect(slipEntry(s, mon, null, now, note: ' after dinner ')?.note, 'after dinner');
      expect(slipEntry(s, mon, null, now, note: '  ')?.note, isNull);
    });
  });

  group('skipping a day', () {
    test('is logged, and tapping it again takes it back', () {
      final e = skipEntry(tick, mon, null, now);
      expect(e?.state, EntryState.skipped);
      expect(skipEntry(tick, mon, e, now), isNull);
    });
  });

  group('keeping what was already there', () {
    test('logging again keeps a note and a photo written earlier that day', () {
      final before = Entry(
        habitId: 'w',
        day: mon,
        state: EntryState.partial,
        value: 3,
        note: 'before lunch',
        photoPath: 'x.jpg',
        loggedAt: now,
      );
      final e = numberEntry(water, mon, 8, now.add(const Duration(hours: 3)), existing: before);
      expect((e?.note, e?.photoPath, e?.state), ('before lunch', 'x.jpg', EntryState.done));
    });

    test('a photo keeps the note, and a note keeps the photo', () {
      final before = Entry(habitId: 'p', day: mon, state: EntryState.done, note: 'sunrise', photoPath: 'old.jpg', loggedAt: now);
      final p = habit('p', logType: LogType.photo);
      expect(photoEntry(p, mon, 'new.jpg', now, existing: before).note, 'sunrise');
      expect(noteEntry(p, mon, 'cloudy', now, existing: before)?.photoPath, 'old.jpg');
    });
  });
}
