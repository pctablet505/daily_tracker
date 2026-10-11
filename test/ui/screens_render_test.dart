import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/ui/screens/backup_screen.dart';
import 'package:daily_tracker/ui/screens/habit_detail_screen.dart';
import 'package:daily_tracker/ui/screens/habit_edit_screen.dart';
import 'package:daily_tracker/ui/screens/habits_screen.dart';
import 'package:daily_tracker/ui/screens/lock_screen.dart';
import 'package:daily_tracker/ui/screens/onboarding_screen.dart';
import 'package:daily_tracker/ui/screens/packs_screen.dart';
import 'package:daily_tracker/ui/screens/progress_screen.dart';
import 'package:daily_tracker/ui/screens/settings_screen.dart';
import 'package:daily_tracker/ui/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Every screen has to draw without overflow or exceptions, in light and dark,
/// at normal and double text size, on a small phone.
void main() {
  setUpAll(loadAppFont);

  final screens = <String, Widget Function()>{
    'Today': () => const Scaffold(body: TodayScreen()),
    'Progress': () => const Scaffold(body: ProgressScreen()),
    'Habits': () => const Scaffold(body: HabitsScreen()),
    'Habit page (number)': () => const HabitDetailScreen(habitId: 'weight'),
    'Habit page (tick)': () => const HabitDetailScreen(habitId: 'run'),
    'Habit page (photo)': () => const HabitDetailScreen(habitId: 'photo'),
    'Habit page (stay clear)': () => const HabitDetailScreen(habitId: 'sugar'),
    'New habit': () => const HabitEditScreen(),
    'Edit habit': () => const HabitEditScreen(habitId: 'water'),
    'Starter packs': () => const PacksScreen(),
    'Settings': () => const SettingsScreen(),
    'Backup': () => const BackupScreen(),
    'First run': () => const OnboardingScreen(),
    'Lock': () => const LockScreen(),
  };

  for (final entry in screens.entries) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('${entry.key} at ${scale}x text, ${brightness.name}', (
          tester,
        ) async {
          final overrides = await baseOverrides(
            ledger: sampleLedger(),
            prefs: {'lockOn': true},
          );
          final errors = await collectFrameworkErrors(
            () => pumpScreen(
              tester,
              entry.value(),
              overrides: overrides,
              textScale: scale,
              brightness: brightness,
              size: const Size(360, 640),
            ),
          );
          expect(errors, isEmpty, reason: errors.join('\n'));
        });
      }
    }
  }

  testWidgets('Today with no habits at all draws, at double text size', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const Scaffold(body: TodayScreen()),
      overrides: await baseOverrides(
        ledger: Ledger(habits: const [], entries: const []),
      ),
      textScale: 2,
      size: const Size(360, 640),
    );
    expect(find.text('Nothing to track yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Today shows the three sections and the summary for the sample week',
    (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: TodayScreen()),
        overrides: await baseOverrides(ledger: sampleLedger()),
        size: const Size(360, 2000),
      );
      expect(find.text('Sunday'.toUpperCase()), findsOneWidget);
      expect(find.text('11 October'), findsOneWidget);
      expect(find.text('TO DO'), findsOneWidget);
      expect(find.text('STAYING CLEAR'), findsOneWidget);
      expect(find.text('Drink water'), findsOneWidget);
      expect(find.text('Morning · 3 of 8 glasses'), findsOneWidget);
      expect(find.text('No added sugar'), findsOneWidget);
      // Weekday-only habit is not planned for a Sunday.
      expect(find.text('Read for twenty minutes before bed'), findsNothing);
    },
  );
}
