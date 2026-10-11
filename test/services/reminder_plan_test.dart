import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

Ledger ledger(List<Habit> habits, [List<Entry> entries = const []]) =>
    Ledger(habits: habits, entries: entries);

Habit remind(
  String id,
  int minutes, {
  int mask = Habit.everyDay,
  DayKey? created,
  DayKey? end,
}) => habit(
  id,
  mask: mask,
  created: created ?? mon,
  end: end,
).copyWith(reminderMinutes: () => minutes);

void main() {
  const noCheckIn = Settings(eveningCheckInOn: false);

  List<PlannedReminder> plan(
    List<Habit> habits, {
    List<Entry> entries = const [],
    Settings settings = noCheckIn,
    DateTime? now,
    int days = 3,
  }) => planReminders(
    ledger(habits, entries),
    settings: settings,
    now: now ?? DateTime(2026, 10, 11, 6),
    horizonDays: days,
  );

  test('one reminder per day at the habit time, over the horizon', () {
    final p = plan([remind('a', 8 * 60)]);
    expect(p.map((r) => r.when), [
      DateTime(2026, 10, 11, 8),
      DateTime(2026, 10, 12, 8),
      DateTime(2026, 10, 13, 8),
    ]);
    expect(p.first.title, 'Habit a');
    expect(p.first.habitId, 'a');
  });

  test('a time that has already passed today starts tomorrow', () {
    final p = plan([remind('a', 8 * 60)], now: DateTime(2026, 10, 11, 9));
    expect(p.first.when, DateTime(2026, 10, 12, 8));
    expect(p.length, 2);
  });

  test('a time exactly now is already past', () {
    expect(
      plan([remind('a', 8 * 60)], now: DateTime(2026, 10, 11, 8)).first.when,
      DateTime(2026, 10, 12, 8),
    );
  });

  test('only on the scheduled weekdays', () {
    final p = plan([
      remind('a', 8 * 60, mask: daysOf([1])),
    ], days: 8);
    expect(p.map((r) => r.when.weekday).toSet(), {DateTime.monday});
    expect(p.length, 1); // Sunday the 11th is the start; Monday the 12th is the only Monday inside 8 days
  });

  test('not for a habit without a reminder time', () {
    expect(plan([habit('a')]), isEmpty);
  });

  test('not for an archived habit past its end day, nor before it begins', () {
    expect(plan([remind('a', 8 * 60, end: sat)]), isEmpty);
    final soon = plan([
      remind('a', 8 * 60, created: const DayKey(2026, 10, 12)),
    ]);
    expect(soon.first.when, DateTime(2026, 10, 12, 8));
  });

  test(
    'not for a stay-clear habit that logs slips; the check-in covers it',
    () {
      expect(
        plan([stayClear('s').copyWith(reminderMinutes: () => 480)]),
        isEmpty,
      );
    },
  );

  test('a habit already done or skipped today is not reminded again today', () {
    final a = remind('a', 20 * 60);
    expect(
      plan(
        [a],
        entries: [entry('a', sun)],
        now: DateTime(2026, 10, 11, 6),
      ).first.when,
      DateTime(2026, 10, 12, 20),
    );
    expect(
      plan([a], entries: [entry('a', sun, EntryState.skipped)]).first.when,
      DateTime(2026, 10, 12, 20),
    );
    expect(
      plan([a], entries: [entry('a', sun, EntryState.partial, 3)]).first.when,
      DateTime(2026, 10, 11, 20),
      reason: 'partial progress still needs finishing',
    );
  });

  group('quiet hours', () {
    const quiet = Settings(
      eveningCheckInOn: false,
      quietHoursOn: true,
      quietStartMinutes: 22 * 60,
      quietEndMinutes: 7 * 60,
    );

    test('a reminder inside the quiet window moves to when it ends', () {
      expect(
        plan([remind('a', 23 * 60)], settings: quiet).first.when,
        DateTime(2026, 10, 12, 7),
        reason: 'late evening moves to the next morning',
      );
      expect(
        plan([remind('a', 6 * 60 + 30)], settings: quiet).first.when,
        DateTime(2026, 10, 11, 7),
        reason: 'early morning moves to the end of the window the same day',
      );
    });

    test('the window edges: start is quiet, end is not', () {
      expect(
        plan([remind('a', 22 * 60)], settings: quiet).first.when,
        DateTime(2026, 10, 12, 7),
      );
      expect(
        plan(
          [remind('a', 7 * 60)],
          settings: quiet,
          now: DateTime(2026, 10, 11, 6),
        ).first.when,
        DateTime(2026, 10, 11, 7),
      );
    });

    test('outside the window nothing moves', () {
      expect(
        plan([remind('a', 12 * 60)], settings: quiet).first.when,
        DateTime(2026, 10, 11, 12),
      );
    });

    test('a window that does not cross midnight works too', () {
      const day = Settings(
        eveningCheckInOn: false,
        quietHoursOn: true,
        quietStartMinutes: 13 * 60,
        quietEndMinutes: 15 * 60,
      );
      expect(
        plan([remind('a', 14 * 60)], settings: day).first.when,
        DateTime(2026, 10, 11, 15),
      );
      expect(
        plan([remind('a', 16 * 60)], settings: day).first.when,
        DateTime(2026, 10, 11, 16),
      );
    });

    test('quiet hours off means no shifting', () {
      const off = Settings(eveningCheckInOn: false, quietHoursOn: false);
      expect(
        plan([remind('a', 23 * 60)], settings: off).first.when,
        DateTime(2026, 10, 11, 23),
      );
    });

    test('start equal to end means no quiet window', () {
      const same = Settings(
        eveningCheckInOn: false,
        quietHoursOn: true,
        quietStartMinutes: 8 * 60,
        quietEndMinutes: 8 * 60,
      );
      expect(
        plan([remind('a', 8 * 60)], settings: same).first.when,
        DateTime(2026, 10, 11, 8),
      );
    });
  });

  group('the evening check-in', () {
    const on = Settings(eveningCheckInOn: true, eveningCheckInMinutes: 21 * 60);

    test('one a day at the chosen time while there is a stay-clear habit', () {
      final p = plan([stayClear('s')], settings: on);
      expect(p.map((r) => r.when), [
        DateTime(2026, 10, 11, 21),
        DateTime(2026, 10, 12, 21),
        DateTime(2026, 10, 13, 21),
      ]);
      expect(p.first.kind, ReminderKind.checkIn);
      expect(p.first.habitId, isNull);
    });

    test('none without a stay-clear habit, or when switched off', () {
      expect(plan([habit('a')], settings: on), isEmpty);
      expect(plan([stayClear('s')], settings: noCheckIn), isEmpty);
    });

    test('not on a day after the stay-clear habit ended', () {
      expect(
        plan([stayClear('s', end: sun)], settings: on).map((r) => r.when),
        [DateTime(2026, 10, 11, 21)],
      );
    });

    test('it is a quiet-hours reminder too', () {
      const late = Settings(
        eveningCheckInOn: true,
        eveningCheckInMinutes: 22 * 60 + 30,
        quietHoursOn: true,
      );
      expect(
        plan([stayClear('s')], settings: late).first.when,
        DateTime(2026, 10, 12, 7),
      );
    });
  });

  group('switches', () {
    test('reminders off plans nothing at all, check-in included', () {
      const off = Settings(remindersOn: false, eveningCheckInOn: true);
      expect(
        plan([remind('a', 8 * 60), stayClear('s')], settings: off),
        isEmpty,
      );
    });
  });

  test('ids are 1, 2, 3 ... in time order, so they are unique and the plan is repeatable', () {
    final habits = [for (var i = 0; i < 12; i++) remind('h$i', 8 * 60 + i)];
    final a = plan(habits, days: 14);
    expect(a.map((r) => r.id), [for (var i = 1; i <= a.length; i++) i]);
    expect(plan(habits, days: 14).map((r) => r.id), a.map((r) => r.id));
  });

  test('the order is by time, so the soonest comes first', () {
    final p = plan([remind('b', 9 * 60), remind('a', 8 * 60)], days: 2);
    expect(p.map((r) => r.when), [
      DateTime(2026, 10, 11, 8),
      DateTime(2026, 10, 11, 9),
      DateTime(2026, 10, 12, 8),
      DateTime(2026, 10, 12, 9),
    ]);
  });

  test('a longer horizon gives more days', () {
    expect(plan([remind('a', 8 * 60)], days: 14).length, 14);
    expect(plan([remind('a', 8 * 60)], days: 0), isEmpty);
  });

  test('only a tick habit can be finished from its notification', () {
    final tick = remind('t', 8 * 60);
    final number = habit(
      'n',
      logType: LogType.number,
    ).copyWith(reminderMinutes: () => 8 * 60);
    final p = plan([tick, number], days: 1);
    expect({for (final r in p) r.habitId: r.markable}, {'t': true, 'n': false});
    const on = Settings(eveningCheckInOn: true);
    expect(
      plan([stayClear('s')], settings: on, days: 1).single.markable,
      isFalse,
    );
  });

  test('the payload says what to open', () {
    final p = plan(
      [remind('a', 8 * 60), stayClear('s')],
      settings: const Settings(eveningCheckInOn: true),
      days: 1,
    );
    expect(p.map((r) => r.payload).toSet(), {'habit:a', 'today'});
  });
}
