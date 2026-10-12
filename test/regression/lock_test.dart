// Regression tests for defects found in review. Each test states the behaviour the app
// promises; a red result is a finding.
import 'dart:async';

import 'package:daily_tracker/services/lock.dart';
import 'package:daily_tracker/state/lock_controller.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lock_test.dart' show FakeBiometrics;

void main() {
  test(
    'leaving the phone for 5 hours from the share sheet still locks the app',
    () async {
      var now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = LockService(
        prefs: prefs,
        biometrics: FakeBiometrics(),
        now: () => now,
      );
      await lock.setPin('1234');
      await const Settings(lockOn: true, lockAfterSeconds: 60).write(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          lockServiceProvider.overrideWithValue(lock),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      expect(c.read(lockedProvider), isFalse);

      // "Save a backup file" -> share sheet -> user picks Gmail and walks away.
      final shareSheet = Completer<void>();
      final job = n.runExternal(() => shareSheet.future);
      n.paused();
      now = now.add(const Duration(hours: 5));
      n.resumed(); // someone else picks up the phone
      shareSheet.complete(); // the share call returns once back in the app
      await job;
      expect(
        c.read(lockedProvider),
        isTrue,
        reason: '5 hours away with "lock after 1 minute" and the data is open',
      );
    },
  );

  test(
    'same, when Android delivers the share result before "resumed"',
    () async {
      var now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = LockService(
        prefs: prefs,
        biometrics: FakeBiometrics(),
        now: () => now,
      );
      await lock.setPin('1234');
      await const Settings(lockOn: true, lockAfterSeconds: 60).write(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          lockServiceProvider.overrideWithValue(lock),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      final shareSheet = Completer<void>();
      final job = n.runExternal(() => shareSheet.future);
      n.paused();
      now = now.add(const Duration(hours: 5));
      shareSheet.complete(); // onActivityResult first
      await job;
      n.resumed(); // then onResume
      expect(
        c.read(lockedProvider),
        isTrue,
        reason: '5 hours away, not locked',
      );
    },
  );
}
