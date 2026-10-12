import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/logic/habit_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

void main() {
  HabitForm form({String name = 'Read', HabitKind kind = HabitKind.build}) =>
      HabitForm(name: name, kind: kind);

  group('validation', () {
    test('a name is required and cannot be blank', () {
      expect(form(name: '').nameError, isNotNull);
      expect(form(name: '   ').nameError, isNotNull);
      expect(form().nameError, isNull);
    });

    test('a name is at most 60 characters once trimmed', () {
      expect(form(name: 'x' * 60).nameError, isNull);
      expect(form(name: 'x' * 61).nameError, isNotNull);
      expect(form(name: '  ${'x' * 60}  ').nameError, isNull);
    });

    test('at least one day must be chosen', () {
      expect(form().copyWith(daysMask: 0).daysError, isNotNull);
      expect(form().copyWith(daysMask: daysOf([3])).daysError, isNull);
    });

    test('a goal, when given, must be a positive number', () {
      HabitForm number(String goal) =>
          form().copyWith(logType: LogType.number, goalText: goal);
      expect(number('').goalError, isNull);
      expect(number('8').goalError, isNull);
      expect(number('2.5').goalError, isNull);
      expect(
        number('2,5').goalError,
        isNull,
        reason: 'a decimal comma is accepted',
      );
      expect(number('0,500').goalError, isNull);
      expect(number('0').goalError, isNotNull);
      expect(number('-3').goalError, isNotNull);
      expect(number('abc').goalError, isNotNull);
      expect(number('Infinity').goalError, isNotNull);
      expect(number('10000000').goalError, isNotNull);
    });

    test('a goal is not checked when the habit is not a number habit', () {
      expect(form().copyWith(goalText: 'abc').goalError, isNull);
    });

    test('valid means no errors at all', () {
      expect(form().isValid, isTrue);
      expect(form(name: '').isValid, isFalse);
      expect(form().copyWith(daysMask: 0).isValid, isFalse);
      expect(
        form(kind: HabitKind.avoid).copyWith(daysMask: 0).isValid,
        isTrue,
        reason: 'stay-clear habits are always every day',
      );
    });
  });

  group('building the habit', () {
    final base = habit('h1', created: mon);

    test(
      'trims the text and keeps the id and start day of the habit being edited',
      () {
        final h = form(name: '  Read  ')
            .copyWith(description: '  a chapter ', area: ' Mind ')
            .toHabit(base);
        expect(
          (h.id, h.createdDay, h.name, h.description, h.area),
          ('h1', mon, 'Read', 'a chapter', 'Mind'),
        );
      },
    );

    test('blank description and area become null', () {
      final h = form().copyWith(description: '  ', area: '').toHabit(base);
      expect((h.description, h.area), (null, null));
    });

    test('a number habit keeps its unit and goal; others drop them', () {
      final n = form()
          .copyWith(logType: LogType.number, unit: ' glasses ', goalText: '8')
          .toHabit(base);
      expect((n.logType, n.unit, n.goal), (LogType.number, 'glasses', 8.0));
      final t = form()
          .copyWith(logType: LogType.tick, unit: 'glasses', goalText: '8')
          .toHabit(base);
      expect((t.unit, t.goal), (null, null));
    });

    test('a decimal comma is read as a point', () {
      expect(
        form()
            .copyWith(logType: LogType.number, goalText: '2,5')
            .toHabit(base)
            .goal,
        2.5,
      );
      expect(
        form()
            .copyWith(logType: LogType.number, goalText: '0,500')
            .toHabit(base)
            .goal,
        0.5,
      );
    });

    test('a stay-clear habit that logs slips is always a tick habit with no reminder', () {
      final h = form(kind: HabitKind.avoid)
          .copyWith(
            avoidMode: AvoidMode.track,
            logType: LogType.number,
            unit: 'cups',
            goalText: '2',
            daysMask: 0,
            reminderMinutes: () => 480,
          )
          .toHabit(base);
      expect(
        (h.logType, h.unit, h.goal, h.reminderMinutes, h.tracksSlips, h.daysMask),
        (LogType.tick, null, null, null, true, Habit.everyDay),
      );
    });

    test('a stay-clear habit in confirm mode can keep a reminder', () {
      final h = form(kind: HabitKind.avoid)
          .copyWith(avoidMode: AvoidMode.confirm, reminderMinutes: () => 480)
          .toHabit(base);
      expect(
        (h.avoidMode, h.reminderMinutes, h.tracksSlips),
        (AvoidMode.confirm, 480, false),
      );
    });

    test('a Do habit keeps its avoidMode from being track so it is never read as stay-clear', () {
      expect(
        form().copyWith(avoidMode: AvoidMode.track).toHabit(base).tracksSlips,
        isFalse,
      );
    });

    test('schedule, part of day and reminder are copied', () {
      final h = form()
          .copyWith(
            daysMask: Habit.weekdaysOnly,
            dayPart: DayPart.evening,
            reminderMinutes: () => 21 * 60,
          )
          .toHabit(base);
      expect(
        (h.daysMask, h.dayPart, h.reminderMinutes),
        (Habit.weekdaysOnly, DayPart.evening, 21 * 60),
      );
    });

    test('keeps the position and end day of the habit being edited', () {
      final archived = base.copyWith(sortOrder: 4, endDay: () => tue);
      final h = form().toHabit(archived);
      expect((h.sortOrder, h.endDay), (4, tue));
    });
  });

  group('starting from a habit', () {
    test('fromHabit then toHabit gives the same habit back', () {
      final h =
          habit(
            'h1',
            kind: HabitKind.build,
            logType: LogType.number,
            goal: 8,
            area: 'Health',
          ).copyWith(
            unit: () => 'glasses',
            description: () => 'daily',
            reminderMinutes: () => 480,
            dayPart: DayPart.morning,
          );
      expect(HabitForm.fromHabit(h).toHabit(h), h);
    });

    test('a stay-clear habit comes back as stay-clear', () {
      final s = stayClear('s');
      expect(HabitForm.fromHabit(s).toHabit(s), s);
    });
  });
}
