import 'dart:ui' show Tristate;

import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/ui/screens/habit_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFont);

  Future<void> pumpNew(WidgetTester tester) async => pumpScreen(
    tester,
    const HabitEditScreen(),
    overrides: await baseOverrides(
      ledger: Ledger(habits: const [], entries: const []),
    ),
    size: const Size(360, 2000),
  );

  bool picked(WidgetTester tester, String day) =>
      tester
          .getSemantics(find.bySemanticsLabel(day))
          .flagsCollection
          .isSelected ==
      Tristate.isTrue;

  testWidgets(
    'the day picker stays while the picks make every day or weekdays',
    (tester) async {
      await pumpNew(tester);
      final semantics = tester.ensureSemantics();
      await tester.tap(find.text('Pick days'));
      await tester.pumpAndSettle();
      // Every day was chosen before, so every day starts picked.
      for (final d in ['Monday', 'Sunday']) {
        expect(picked(tester, d), isTrue, reason: d);
      }
      await tester.tap(find.bySemanticsLabel('Sunday'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Sunday'));
      await tester.pumpAndSettle();
      // All seven picked again: the picker must not vanish under the finger.
      expect(find.bySemanticsLabel('Sunday'), findsOneWidget);
      // Nor at Monday to Friday.
      for (final d in ['Saturday', 'Sunday']) {
        await tester.tap(find.bySemanticsLabel(d));
        await tester.pumpAndSettle();
      }
      expect(find.bySemanticsLabel('Sunday'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Tuesday'));
      await tester.pumpAndSettle();
      // Tapping "Pick days" again keeps the picks.
      await tester.tap(find.text('Pick days'));
      await tester.pumpAndSettle();
      expect(picked(tester, 'Tuesday'), isFalse);
      expect(picked(tester, 'Monday'), isTrue);
      semantics.dispose();
    },
  );

  testWidgets('a too-long unit, area or note is pointed out on save', (
    tester,
  ) async {
    await pumpNew(tester);
    await tester.enterText(find.byType(TextField).first, 'Read');
    await tester.tap(find.text('Number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Unit'), 'x' * 13);
    await tester.enterText(
      find.widgetWithText(TextField, 'Health, Mind, Work...'),
      'x' * 41,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Why this matters, or what counts'),
      'x' * 201,
    );
    await tester.tap(find.text('Add habit'));
    await tester.pumpAndSettle();
    expect(find.text('Keep it under 12 characters'), findsOneWidget);
    expect(find.text('Keep it under 40 characters'), findsOneWidget);
    expect(find.text('Keep it under 200 characters'), findsOneWidget);
  });
}
