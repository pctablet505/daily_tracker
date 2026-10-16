import 'dart:ui' show Tristate;

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/logic/habit_form.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/ui/screens/habit_edit_screen.dart';
import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import 'harness.dart';

void main() {
  sqfliteFfiInit();
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

  testWidgets('the area chips leave out an area over the limit', (
    tester,
  ) async {
    // Areas kept from 2.0.2, which had no limit; picking the long one would be refused.
    final long = 'L' * (HabitForm.maxAreaLength + 1);
    final most = 'M' * HabitForm.maxAreaLength;
    await pumpScreen(
      tester,
      const HabitEditScreen(),
      overrides: await baseOverrides(
        ledger: Ledger(
          habits: [
            habit('a').copyWith(area: () => long),
            habit('b').copyWith(area: () => most),
          ],
          entries: const [],
        ),
      ),
      size: const Size(360, 2000),
    );
    expect(find.widgetWithText(ActionChip, most), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Health'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, long), findsNothing);
  });

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

  testWidgets(
    'a refused save brings the field in error into view and says why',
    (tester) async {
      final h = habit('read');
      await pumpScreen(
        tester,
        HabitEditScreen(habitId: h.id),
        overrides: await baseOverrides(
          ledger: Ledger(habits: [h], entries: const []),
        ),
      );
      await tester.pumpAndSettle();
      // A new note over the limit, typed at the bottom of the form.
      final note = find.widgetWithText(
        TextField,
        'Why this matters, or what counts',
      );
      final form = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(note, 200, scrollable: form);
      await tester.enterText(note, 'x' * 201);
      // The keyboard closes: a focused field would be kept alive off screen.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // Back at the top, change something and save.
      await tester.drag(form, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evening'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Save changes'), findsOneWidget, reason: 'not saved');
      expect(find.text('Check the fields marked in red.'), findsOneWidget);
      final error = find.text('Keep it under 200 characters');
      expect(error, findsOneWidget);
      final rect = tester.getRect(error);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(
        rect.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Save changes')).top),
        reason: 'the error is on screen, above the Save bar',
      );
    },
  );

  testWidgets('an old habit with a note over the limit saves with all of it', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
        singleInstance: false,
      ),
    ))!;
    addTearDown(() => tester.runAsync(db.close));
    // A habit kept from 2.0.2, whose note had no limit then.
    final old = habit('read').copyWith(description: () => 'n' * 319);
    await tester.runAsync(() => HabitRepository(db).addHabit(old));
    final overrides = (await baseOverrides())
      // The harness's unused database.
      ..removeAt(0)
      ..add(databaseProvider.overrideWithValue(db));
    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(
          path: '/edit',
          builder: (_, _) => HabitEditScreen(habitId: old.id),
        ),
      ],
    );
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 20 && find.text('Evening').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    await tester.tap(find.text('Evening'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    // The write needs real time.
    for (var i = 0; i < 20 && find.text('HOME').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('HOME'), findsOneWidget, reason: 'the save went through');
    final saved = (await tester.runAsync(() => HabitRepository(db).habits()))!
        .single;
    expect(saved.dayPart, DayPart.evening);
    expect(saved.description, 'n' * 319);
  });
}
