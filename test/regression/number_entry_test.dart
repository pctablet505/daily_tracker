// Regression tests for defects found in review. Each test states the behaviour the app
// promises; a red result is a finding.
import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/logic/habit_form.dart';
import 'package:daily_tracker/ui/format.dart';
import 'package:daily_tracker/ui/number_input.dart';
import 'package:daily_tracker/ui/sheets/entry_sheets.dart';
import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('number sheet with amounts of 1,000 or more', () {
    test('an existing 1,500 opens as a value that can be saved', () {
      // The sheet seeds the input with plainAmount; formatAmount's comma cannot be parsed.
      expect(formatAmount(1500), '1,500');
      final seeded = NumberInput(plainAmount(1500));
      expect(seeded.text, '1500');
      expect(seeded.value, 1500);
    });

    test('plainAmount drops separators and trailing zeros, keeps decimals', () {
      expect(plainAmount(8000), '8000');
      expect(plainAmount(2.5), '2.5');
      expect(plainAmount(0.25), '0.25');
      expect(plainAmount(100), '100');
      expect(plainAmount(1234567), '1234567');
    });

    test('+1 on 999 gives 1,000, not an unreadable value', () {
      expect(const NumberInput('999').adjust(1).value, 1000);
    });

    test('+1 on an existing 8,000 steps gives 8,001, not 1', () {
      expect(NumberInput(plainAmount(8000)).adjust(1).value, 8001);
    });

    testWidgets(
      'the Save button works when re-opening a day with 8,000 steps',
      (tester) async {
        const day = DayKey(2026, 10, 11);
        final steps = Habit(
          id: 's',
          name: 'Walk 10,000 steps',
          createdDay: day,
          logType: LogType.number,
          unit: 'steps',
          goal: 10000,
        );
        double? result = -1;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showNumberSheet(
                      context,
                      habit: steps,
                      day: day,
                      today: day,
                      current: 8000,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final save = find.ancestor(
          of: find.textContaining('Save'),
          matching: find.byType(FilledButton),
        );
        expect(save, findsOneWidget);
        expect(
          tester.widget<FilledButton>(save).onPressed,
          isNotNull,
          reason: 'Save is disabled for an existing 8,000-step entry',
        );
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(result, 8000);
      },
    );
  });

  test('a goal typed as "10,000" is ten thousand, or refused; never 10', () {
    const f = HabitForm(
      name: 'Walk',
      logType: LogType.number,
      goalText: '10,000',
    );
    expect(f.goal, 10000);
    expect(f.goalError, isNull);
  });

  test(
    'goal text reads thousands separators, decimal points and decimal commas',
    () {
      double? goalOf(String t) =>
          HabitForm(name: 'x', logType: LogType.number, goalText: t).goal;
      expect(goalOf('10000'), 10000);
      expect(goalOf('2,500.5'), 2500.5);
      expect(goalOf('1,234,567'), 1234567);
      expect(goalOf('2,5'), 2.5);
      expect(goalOf('0.5'), 0.5);
      expect(goalOf(' 8 '), 8);
      expect(goalOf('abc'), isNull);
      expect(goalOf(''), isNull);
    },
  );
}
