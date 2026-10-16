import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:daily_tracker/app.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/services/photo_picker.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/ui/screens/today_screen.dart';
import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import 'harness.dart';

Future<void> _pumpToday(
  WidgetTester tester,
  Ledger ledger, {
  DateTime? now,
  double textScale = 1,
}) async {
  await pumpScreen(
    tester,
    const Scaffold(body: TodayScreen()),
    overrides: await baseOverrides(ledger: ledger, now: now),
    textScale: textScale,
    size: const Size(360, 1200),
  );
}

/// Records the haptic feedback the app asks for.
List<String> _recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add('${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return haptics;
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('finishing the last habit of today celebrates', (tester) async {
    final haptics = _recordHaptics(tester);
    final run = habit('run');
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      overrides: [
        ...await baseOverrides(),
        ledgerByRevision(
          Ledger(habits: [run], entries: const [], seenDays: [sun]),
          Ledger(habits: [run], entries: [entry('run', sun)], seenDays: [sun]),
        ),
      ],
    );
    bumpRevision(tester);
    // Not pumpAndSettle: the confetti animates for seconds.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('1 of 1 done'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.heavyImpact'));
  });

  // Today inside the app's shell: it celebrates only where it can be seen.
  for (final (over, shown) in [
    ('nothing', true),
    ('/habit/run', false),
    ('/settings', false),
    ('/progress', false),
    ('the habit menu', false),
  ]) {
    testWidgets('celebrates with $over over Today: $shown', (tester) async {
      final haptics = _recordHaptics(tester);
      final run = habit('run');
      final router = buildRouter(onboardingDone: () => true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await baseOverrides(),
            ledgerByRevision(
              Ledger(habits: [run], entries: const [], seenDays: [sun]),
              Ledger(
                habits: [run],
                entries: [entry('run', sun)],
                seenDays: [sun],
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: buildTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TO DO'), findsOneWidget);
      switch (over) {
        case '/progress':
          router.go(over);
        case 'the habit menu':
          await tester.tap(find.text('Habit run'));
        case 'nothing':
          break;
        default:
          unawaited(router.push(over));
      }
      await tester.pumpAndSettle();

      // A notification's Done button writes while Today is out of sight.
      bumpRevision(tester);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(haptics.contains('HapticFeedbackType.heavyImpact'), shown);
    });
  }

  testWidgets('a write keeps the list and its scroll position', (tester) async {
    final habits = [for (var i = 0; i < 25; i++) habit('h$i')];
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      overrides: [
        ...await baseOverrides(),
        ledgerByRevision(
          Ledger(habits: habits, entries: const [], seenDays: [sun]),
          Ledger(habits: habits, entries: [entry('h24', sun)], seenDays: [sun]),
        ),
      ],
    );
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -3000));
    await tester.pumpAndSettle();
    final scrolled = tester.state<ScrollableState>(list).position.pixels;
    expect(scrolled, greaterThan(500));

    bumpRevision(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(list).position.pixels, scrolled);
  });

  testWidgets('the slip toast with its Undo goes away by itself', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => openAppDatabase(databaseFactoryFfiNoIsolate, inMemoryDatabasePath),
    ))!;
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(
      () => HabitRepository(db).addHabit(stayClear('sugar')),
    );
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      // The first base override is the stand-in database; use the real one.
      overrides: [
        databaseProvider.overrideWithValue(db),
        ...(await baseOverrides()).skip(1),
      ],
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Slipped'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a past day the app never saw asks whether it stayed clear', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => openAppDatabase(databaseFactoryFfiNoIsolate, inMemoryDatabasePath),
    ))!;
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() async {
      final repo = HabitRepository(db);
      await repo.addHabit(stayClear('sugar'));
      // Wednesday was never seen.
      for (final d in [mon, tue, thu, fri, sat, sun]) {
        await repo.markSeen(d);
      }
    });
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      overrides: [
        databaseProvider.overrideWithValue(db),
        ...(await baseOverrides()).skip(1),
      ],
    );
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel(RegExp('^7 October')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Editing Wed 7 Oct'), findsOneWidget);
    expect(
      find.text('Staying clear: 0 of 1 on track, 1 not checked'),
      findsOneWidget,
    );
    expect(find.text('Not checked'), findsOneWidget);
    expect(find.text('Slipped'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('I stayed clear'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Staying clear: 1 of 1 on track'), findsOneWidget);
    expect(find.text('Slipped'), findsOneWidget);
  });

  testWidgets('a row that is not checked fits both its buttons at double '
      'text size on a small phone', (tester) async {
    final l = Ledger(
      habits: [stayClear('scroll').copyWith(name: 'No social media scrolling')],
      entries: const [],
      // Only today seen: no streak, so the summary card has no streak chip.
      seenDays: [sun],
    );
    final errors = await collectFrameworkErrors(() async {
      await pumpScreen(
        tester,
        const Scaffold(body: TodayScreen()),
        overrides: await baseOverrides(ledger: l),
        textScale: 2,
        size: const Size(320, 1600),
      );
      ProviderScope.containerOf(tester.element(find.byType(TodayScreen)))
          .read(selectedDayProvider.notifier)
          .select(wed);
      await tester.pumpAndSettle();
    });
    expect(find.text('I stayed clear'), findsOneWidget);
    expect(find.text('Slipped'), findsOneWidget);
    expect(errors, isEmpty, reason: errors.join('\n'));
    // Fitting is not enough: the label itself must not be cut short.
    for (final word in ['I stayed clear', 'Slipped']) {
      expect(
        tester.renderObject<RenderParagraph>(find.text(word)).didExceedMaxLines,
        isFalse,
        reason: word,
      );
    }
  });

  testWidgets('the week strip reads a stay-clear day as the calendar does', (
    tester,
  ) async {
    final l = Ledger(
      habits: [stayClear('sugar')],
      entries: [slip('sugar', tue)],
      seenDays: [mon, tue, thu, sun],
    );
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      overrides: await baseOverrides(ledger: l),
      size: const Size(400, 1600),
    );
    String label(String day) => tester
        .getSemantics(find.bySemanticsLabel(RegExp('(^|, )$day October, ')))
        .label;
    expect(label('5'), endsWith('5 October, on track'));
    expect(label('6'), endsWith('6 October, 1 slip'));
    expect(label('7'), endsWith('7 October, not checked'));
    expect(label('8'), endsWith('8 October, on track'));
  });

  testWidgets('the week strip names a stay-clear habit not answered on a day '
      'with something done', (tester) async {
    final l = Ledger(
      habits: [habit('run'), stayClear('sugar')],
      entries: [entry('run', wed)],
      seenDays: [mon, tue, thu, fri, sat, sun],
    );
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      overrides: await baseOverrides(ledger: l),
      size: const Size(400, 1600),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(RegExp('(^|, )7 October, ')))
          .label,
      endsWith('7 October, 100 percent done, 1 not checked'),
    );
  });

  testWidgets('the photo picker is told which habit and day it is for', (
    tester,
  ) async {
    // So a photo Android kept when it stopped the app can still be logged.
    final asked = <(PhotoSource, String?, DayKey?)>[];
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      overrides: [
        ...await baseOverrides(
          ledger: Ledger(
            habits: [habit('pic', logType: LogType.photo)],
            entries: const [],
          ),
        ),
        photoPickerProvider.overrideWithValue((source, {habitId, day}) async {
          asked.add((source, habitId, day));
          return null;
        }),
      ],
    );
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(asked, [(PhotoSource.camera, 'pic', sun)]);
  });

  testWidgets('a skipped stay-clear day can only be counted again', (
    tester,
  ) async {
    await _pumpToday(
      tester,
      Ledger(
        habits: [stayClear('sugar')],
        entries: [entry('sugar', sun, EntryState.skipped)],
        seenDays: [sun],
      ),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('^Mark done')), findsNothing);
    semantics.dispose();
    // The round mark writes nothing (here a write would fail and say so).
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    expect(find.text('That did not save. Try again.'), findsNothing);
    await tester.tap(find.text('Habit sugar'));
    await tester.pumpAndSettle();
    expect(find.text('Count this day again'), findsOneWidget);
  });

  testWidgets('on a Monday the strip can go back to fill in Sunday', (
    tester,
  ) async {
    await _pumpToday(
      tester,
      Ledger(
        habits: [habit('run', created: thu)],
        entries: const [],
      ),
      now: DateTime(2026, 10, 12, 9),
    );
    final semantics = tester.ensureSemantics();
    final sunday = find.bySemanticsLabel(RegExp('^11 October'));
    expect(sunday, findsNothing);
    expect(
      tester
          .getSemantics(find.byTooltip('Next week'))
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
      reason: 'the week after this one has not happened yet',
    );

    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    // The strip moved; the day shown did not.
    expect(find.text('12 October'), findsOneWidget);
    expect(find.text('Editing Sun 11 Oct'), findsNothing);
    await tester.tap(sunday);
    await tester.pumpAndSettle();
    expect(find.text('Editing Sun 11 Oct'), findsOneWidget);

    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    // This week again, where only today and the days before it can be picked.
    final tuesday = find.bySemanticsLabel(RegExp('^13 October'));
    expect(tester.getSemantics(tuesday).flagsCollection.isButton, isFalse);

    // Going back to today brings the strip back to this week.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();
    }
    expect(tuesday, findsNothing);
    await tester.tap(find.text('Back to today'));
    await tester.pumpAndSettle();
    expect(tuesday, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the Done count fits its badge at double text size', (
    tester,
  ) async {
    final habits = [for (var i = 0; i < 12; i++) habit('h$i')];
    await _pumpToday(
      tester,
      Ledger(
        habits: habits,
        entries: [for (final h in habits) entry(h.id, sun)],
      ),
      textScale: 2,
    );
    final count = tester.renderObject<RenderParagraph>(find.text('12'));
    expect(
      count.size.height,
      greaterThanOrEqualTo(count.getMaxIntrinsicHeight(double.infinity)),
    );
  });

  testWidgets('a failed archive says so and does not claim it worked', (
    tester,
  ) async {
    // The stand-in database fails every write.
    await _pumpToday(tester, Ledger(habits: [habit('run')], entries: const []));
    await tester.tap(find.text('Habit run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('That did not save. Try again.'), findsOneWidget);
    expect(find.textContaining('Archived Habit run'), findsNothing);
  });

  testWidgets('a done tick is not offered "Skip this day"', (tester) async {
    // Taking the skip back could not bring the tick back.
    await _pumpToday(
      tester,
      Ledger(habits: [habit('run')], entries: [entry('run', sun)]),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habit run'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Skip this day'), findsNothing);
  });
}
