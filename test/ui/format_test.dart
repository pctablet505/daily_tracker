import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

void main() {
  test('dates', () {
    expect(weekdayName(sun), 'Sunday');
    expect(longDate(sun), '11 October');
    expect(shortDate(fri), 'Fri 9 Oct');
    expect(monthTitle(sun), 'October 2026');
    expect(
      [for (final d in mon.through(sun)) weekdayLetter(d)],
      ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    );
    expect(longDate(const DayKey(2026, 2, 28)), '28 February');
  });

  group('formatAmount', () {
    for (final c in [
      (75.0, '75'),
      (75.5, '75.5'),
      (0.25, '0.25'),
      (0.1, '0.1'),
      (8.0, '8'),
      (1234.5, '1,234.5'),
      (10000.0, '10,000'),
      (1000000.0, '1,000,000'),
      (999.0, '999'),
      (-3.5, '-3.5'),
      (-0.5, '-0.5'),
      (-0.25, '-0.25'),
      (-0.001, '0'),
      (0.0, '0'),
      (2.999, '3'),
      (double.nan, '0'),
      (double.infinity, '0'),
    ]) {
      test('${c.$1} -> ${c.$2}', () => expect(formatAmount(c.$1), c.$2));
    }
    test('with a unit', () {
      expect(formatAmountUnit(75.5, 'kg'), '75.5 kg');
      expect(formatAmountUnit(8, null), '8');
      expect(formatAmountUnit(8, ''), '8');
    });
  });

  group('formatMinutes', () {
    test('12 and 24 hour', () {
      expect(formatMinutes(0, use24h: false), '12:00 AM');
      expect(formatMinutes(8 * 60, use24h: false), '8:00 AM');
      expect(formatMinutes(12 * 60, use24h: false), '12:00 PM');
      expect(formatMinutes(13 * 60 + 5, use24h: false), '1:05 PM');
      expect(formatMinutes(23 * 60 + 59, use24h: false), '11:59 PM');
      expect(formatMinutes(8 * 60, use24h: true), '08:00');
      expect(formatMinutes(23 * 60 + 59, use24h: true), '23:59');
    });
  });

  test('scheduleSummary', () {
    expect(scheduleSummary(Habit.everyDay), 'Every day');
    expect(scheduleSummary(Habit.weekdaysOnly), 'Weekdays');
    expect(scheduleSummary(daysOf([6, 7])), 'Weekends');
    expect(scheduleSummary(daysOf([1, 3, 5])), 'Mon, Wed, Fri');
    expect(scheduleSummary(0), 'Never');
  });

  group('habitMeta', () {
    final base = habit('a');
    test(
      'tick: part of the day only',
      () => expect(habitMeta(base), 'Anytime'),
    );
    test(
      'part of the day is shown',
      () =>
          expect(habitMeta(base.copyWith(dayPart: DayPart.morning)), 'Morning'),
    );
    test('number: last value', () {
      final w = habit(
        'w',
        logType: LogType.number,
      ).copyWith(unit: () => 'kg', dayPart: DayPart.morning);
      expect(habitMeta(w, lastValue: 75.9), 'Morning · last 75.9 kg');
    });
    test('number with a goal shows progress, or the goal', () {
      final w = habit(
        'w',
        logType: LogType.number,
        goal: 8,
      ).copyWith(unit: () => 'glasses');
      expect(
        habitMeta(w, entry: entry('w', mon, EntryState.partial, 3)),
        'Anytime · 3 of 8 glasses',
      );
      expect(habitMeta(w), 'Anytime · goal 8 glasses');
    });
    test('note and photo', () {
      expect(habitMeta(habit('n', logType: LogType.note)), 'Anytime · note');
      expect(
        habitMeta(habit('p', logType: LogType.photo), photoCount: 31),
        'Anytime · 31 photos',
      );
      expect(
        habitMeta(habit('p', logType: LogType.photo), photoCount: 1),
        'Anytime · 1 photo',
      );
      expect(habitMeta(habit('p', logType: LogType.photo)), 'Anytime');
    });
  });

  test('logActionLabel', () {
    expect(
      logActionLabel(
        habit('w', logType: LogType.number).copyWith(unit: () => 'kg'),
      ),
      'Log kg',
    );
    expect(logActionLabel(habit('w', logType: LogType.number)), 'Log amount');
    expect(logActionLabel(habit('n', logType: LogType.note)), 'Add note');
    expect(logActionLabel(habit('p', logType: LogType.photo)), 'Take photo');
  });
}
