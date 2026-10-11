// Review tests (DT-REVIEW 2026-10-11): the sheets and dialogs that
// screens_render_test.dart never opens, at 2x text on a small phone.
import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/services/updater.dart';
import 'package:daily_tracker/ui/screens/settings_screen.dart';
import 'package:daily_tracker/ui/sheets/entry_sheets.dart';
import 'package:daily_tracker/ui/sheets/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/harness.dart';

void main() {
  setUpAll(loadAppFont);
  const day = DayKey(2026, 10, 11);
  final longName = 'W' * 60; // the longest name the form allows
  final number = Habit(
    id: 'n',
    name: longName,
    createdDay: day,
    logType: LogType.number,
    unit: 'steps',
    goal: 10000,
  );

  final sheets = <String, void Function(BuildContext)>{
    'number sheet': (c) => showNumberSheet(
      c,
      habit: number,
      day: day,
      today: day,
      current: 1234567,
      lastValue: 7654321,
    ),
    'note sheet': (c) => showNoteSheet(
      c,
      habit: number,
      day: day.addDays(-3),
      today: day,
      current: 'x' * 400,
    ),
    'photo sheet': (c) => showPhotoSheet(c, habit: number, hasPhoto: true),
    'habit menu': (c) =>
        showHabitMenu(c, habit: number, skipped: false, canSkip: true),
    'photo sheet, short name "Read"': (c) =>
        showPhotoSheet(c, habit: number.copyWith(name: 'Read'), hasPhoto: true),
    'habit menu, short name "Read"': (c) => showHabitMenu(
      c,
      habit: number.copyWith(name: 'Read'),
      skipped: false,
      canSkip: true,
    ),
    'PIN setup': (c) => showPinSetup(c),
    'PIN entry': (c) =>
        showPinEntry(c, title: 'Enter your PIN to turn the lock off'),
    'update sheet': (c) => showUpdateSheet(
      c,
      const ReleaseInfo(
        version: '2.1.0',
        notes: 'Line\nLine\nLine\nLine\nLine\nLine\nLine\nLine\nLine\nLine',
        apkUrl: 'https://example.test/a.apk',
        apkSize: 25000000,
      ),
      onSkip: () async {},
    ),
  };

  for (final s in sheets.entries) {
    testWidgets('${s.key} draws at 2x text on a 360x640 phone', (tester) async {
      final overrides = await baseOverrides();
      final errors = await collectFrameworkErrors(() async {
        await pumpScreen(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => s.value(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          overrides: overrides,
          textScale: 2,
          size: const Size(360, 640),
        );
        await tester.tap(find.text('open'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
      expect(
        errors,
        isEmpty,
        reason: errors.take(1).join('\n').split('\n').take(12).join('\n'),
      );
    });
  }
}
