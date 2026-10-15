import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fixtures.dart';

void main() {
  // Saturday's check-in at 23:00 falls in the quiet hours and moves to Sunday
  // 07:00, so at 01:00 on Sunday it is still to come.
  const settings = Settings(
    eveningCheckInOn: true,
    eveningCheckInMinutes: 23 * 60,
    quietHoursOn: true,
    quietStartMinutes: 22 * 60,
    quietEndMinutes: 7 * 60,
  );

  List<PlannedReminder> saturdayCheckIns(Ledger l) => [
    for (final r in planReminders(
      l,
      settings: settings,
      now: DateTime(2026, 10, 11, 1),
      horizonDays: 1,
      includeCarryOver: true,
    ))
      if (r.kind == ReminderKind.checkIn && r.forDay == sat) r,
  ];

  test('the moved check-in stays while a stay-clear habit is not checked for that day', () {
    final s = stayClear('s');
    final t = stayClear('t');
    // Another habit was logged on Saturday, and "I stayed clear" answered
    // for s alone: t is still not checked.
    expect(
      saturdayCheckIns(
        Ledger(
          habits: [s, t, habit('run')],
          entries: [entry('run', sat), entry('s', sat)],
        ),
      ),
      hasLength(1),
    );
    expect(
      saturdayCheckIns(
        Ledger(habits: [s, t], entries: [entry('s', sat), entry('t', sat)]),
      ),
      isEmpty,
    );
    expect(
      saturdayCheckIns(
        Ledger(habits: [s, t], entries: const [], seenDays: [sat]),
      ),
      isEmpty,
    );
  });
}
