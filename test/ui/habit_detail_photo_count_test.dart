import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/ui/screens/habit_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFont);

  testWidgets(
    'the photo count leaves out photos whose file is not on this phone',
    (tester) async {
      // Restored on a new phone: the entries name two photos, no file came back.
      final pic = habit('pic', logType: LogType.photo);
      await pumpScreen(
        tester,
        const HabitDetailScreen(habitId: 'pic'),
        overrides: await baseOverrides(
          ledger: Ledger(
            habits: [pic],
            entries: [
              for (final d in [mon, tue])
                entry('pic', d).copyWith(photoPath: () => 'p$d.jpg'),
            ],
          ),
        ),
        size: const Size(360, 2000),
      );
      final semantics = tester.ensureSemantics();
      expect(find.text('PHOTOS, 0'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Photo from')), findsNWidgets(2));
      semantics.dispose();
    },
  );
}
