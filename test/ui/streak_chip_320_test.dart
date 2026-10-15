import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/ui/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';
import '../ui/harness.dart';

void main() {
  setUpAll(loadAppFont);

  // The streak chip in the summary card wrapped nowhere: at 2x text on a small
  // phone its label ran 22 px past the edge.
  testWidgets('Today summary card with a streak fits at 320dp, 2x text', (
    tester,
  ) async {
    final l = Ledger(
      habits: [stayClear('scroll').copyWith(name: 'No social media scrolling')],
      entries: const [],
      seenDays: [mon, sun],
    );
    final errors = await collectFrameworkErrors(
      () async => pumpScreen(
        tester,
        const Scaffold(body: TodayScreen()),
        overrides: await baseOverrides(ledger: l),
        textScale: 2,
        size: const Size(320, 1600),
      ),
    );
    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}
