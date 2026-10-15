import 'package:daily_tracker/services/lock.dart';
import 'package:daily_tracker/state/lock_controller.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lock_test.dart' show FakeBiometrics;

void main() {
  late SharedPreferences prefs;
  late FakeBiometrics bio;
  late LockService lock;
  late ProviderContainer c;
  var now = DateTime(2026, 10, 11, 12);
  // Time since the phone started; null as on a platform without the channel.
  Duration? boot = const Duration(hours: 5);

  Future<void> setup({
    bool lockOn = true,
    bool withPin = true,
    int after = 60,
  }) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    bio = FakeBiometrics();
    lock = LockService(
      prefs: prefs,
      biometrics: bio,
      now: () => now,
      elapsed: () async => boot,
    );
    if (withPin) await lock.setPin('1234');
    await Settings(lockOn: lockOn, lockAfterSeconds: after).write(prefs);
    c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
        elapsedRealtimeProvider.overrideWithValue(() async => boot),
        lockServiceProvider.overrideWithValue(lock),
      ],
    );
    addTearDown(c.dispose);
  }

  setUp(() {
    now = DateTime(2026, 10, 11, 12);
    boot = const Duration(hours: 5);
  });

  /// Real time passes: both clocks move.
  void wait(Duration d) {
    now = now.add(d);
    boot = boot! + d;
  }

  test(
    'a fresh start is locked when the lock is on and a PIN is set',
    () async {
      await setup();
      expect(c.read(lockedProvider), isTrue);
    },
  );

  test(
    'a fresh start is open when the lock is off, or no PIN was ever set',
    () async {
      await setup(lockOn: false);
      expect(c.read(lockedProvider), isFalse);
      await setup(withPin: false);
      expect(c.read(lockedProvider), isFalse);
    },
  );

  test('the right PIN opens it; a wrong one keeps it shut and says how many tries went', () async {
    await setup();
    final n = c.read(lockedProvider.notifier);
    expect((await n.unlockWithPin('0000')).ok, isFalse);
    expect(c.read(lockedProvider), isTrue);
    expect((await n.unlockWithPin('1234')).ok, isTrue);
    expect(c.read(lockedProvider), isFalse);
  });

  test('fingerprint and phone lock open it too', () async {
    await setup();
    bio.result = false;
    expect(
      await c.read(lockedProvider.notifier).unlockWithBiometrics(),
      isFalse,
    );
    expect(c.read(lockedProvider), isTrue);
    bio.result = true;
    expect(
      await c.read(lockedProvider.notifier).unlockWithBiometrics(),
      isTrue,
    );
    expect(c.read(lockedProvider), isFalse);
    c.read(lockedProvider.notifier).lockNow();
    expect(
      await c.read(lockedProvider.notifier).unlockWithDeviceCredential(),
      isTrue,
    );
    expect(c.read(lockedProvider), isFalse);
  });

  group('coming back to the app', () {
    test('a short trip away does not lock; a long one does', () async {
      await setup(after: 60);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      n.paused();
      now = now.add(const Duration(seconds: 30));
      n.resumed();
      expect(c.read(lockedProvider), isFalse);
      n.paused();
      now = now.add(const Duration(seconds: 90));
      n.resumed();
      expect(c.read(lockedProvider), isTrue);
    });

    test('a second "resumed" with no pause in between does not lock on a stale time', () async {
      await setup(after: 60);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      n.paused();
      now = now.add(const Duration(seconds: 30));
      n.resumed();
      now = now.add(const Duration(minutes: 5));
      n.resumed();
      expect(c.read(lockedProvider), isFalse);
    });

    test('"immediately" locks on every return', () async {
      await setup(after: 0);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      n.paused();
      n.resumed();
      expect(c.read(lockedProvider), isTrue);
    });

    test('with the lock off nothing ever locks', () async {
      await setup(lockOn: false, after: 0);
      final n = c.read(lockedProvider.notifier);
      n.paused();
      now = now.add(const Duration(hours: 5));
      n.resumed();
      expect(c.read(lockedProvider), isFalse);
    });

    test('a picker the app opened itself (camera, files) does not count as leaving', () async {
      await setup(after: 0);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      await n.runExternal(() async {
        n.paused();
        now = now.add(const Duration(minutes: 3));
        n.resumed();
      });
      expect(c.read(lockedProvider), isFalse);
      n.paused();
      n.resumed();
      expect(
        c.read(lockedProvider),
        isTrue,
        reason: 'back to normal afterwards',
      );
    });

    test('a short trip to a picker does not lock even with "right away"; a long one does', () async {
      await setup(after: 0);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      await n.runExternal(() async {
        n.paused();
        now = now.add(const Duration(seconds: 40));
        n.resumed();
      });
      expect(c.read(lockedProvider), isFalse);
      await n.runExternal(() async {
        n.paused();
        now = now.add(const Duration(minutes: 6));
        n.resumed();
      });
      expect(c.read(lockedProvider), isTrue);
    });

    test(
      'a result that arrives before "resumed" still counts as a short trip',
      () async {
        await setup(after: 0);
        final n = c.read(lockedProvider.notifier);
        await n.unlockWithPin('1234');
        await n.runExternal(() async => n.paused());
        now = now.add(const Duration(seconds: 40));
        n.resumed();
        expect(c.read(lockedProvider), isFalse);
      },
    );

    test(
      'an app that was killed in the background and restarted is locked',
      () async {
        await setup();
        expect(c.read(lockedProvider), isTrue);
      },
    );

    test('a second pause transition while already in the background keeps the original pause time', () async {
      await setup(after: 60);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      n.paused(); // inactive at t=0
      now = now.add(const Duration(seconds: 40));
      n.paused(); // hidden/paused at t=40s
      now = now.add(const Duration(seconds: 25)); // total 65s > 60s
      n.resumed();
      expect(c.read(lockedProvider), isTrue);
    });

    test('nested runExternal calls keep the external grace window until both finish', () async {
      await setup(after: 0);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      await n.runExternal(() async {
        await n.runExternal(() async {});
        n.paused();
        now = now.add(const Duration(seconds: 30));
        n.resumed();
      });
      expect(c.read(lockedProvider), isFalse);
    });

    test(
      'setting the clock back while away does not hide the time away',
      () async {
        await setup(after: 60);
        final n = c.read(lockedProvider.notifier);
        await n.unlockWithPin('1234');
        n.paused();
        wait(const Duration(minutes: 10));
        now = now.subtract(const Duration(minutes: 9, seconds: 30));
        n.resumed();
        await n.settled;
        expect(c.read(lockedProvider), isTrue);
      },
    );

    test('a short trip by both clocks stays open', () async {
      await setup(after: 60);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      n.paused();
      wait(const Duration(seconds: 30));
      n.resumed();
      await n.settled;
      expect(c.read(lockedProvider), isFalse);
    });

    test('without the boot clock the wall clock alone decides', () async {
      boot = null;
      await setup(after: 60);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      n.paused();
      now = now.add(const Duration(seconds: 30));
      n.resumed();
      await n.settled;
      expect(c.read(lockedProvider), isFalse);
      n.paused();
      now = now.add(const Duration(seconds: 90));
      n.resumed();
      await n.settled;
      expect(c.read(lockedProvider), isTrue);
    });

    test(
      'a job that never leaves the app gives no grace to a later Home press',
      () async {
        await setup(after: 0);
        final n = c.read(lockedProvider.notifier);
        await n.unlockWithPin('1234');
        // A permission that is already granted: no pause, no resume.
        await n.runExternal(() async => true);
        wait(const Duration(seconds: 3));
        n.paused();
        wait(const Duration(minutes: 4));
        n.resumed();
        expect(
          c.read(lockedProvider),
          isTrue,
          reason: '"Right away" must lock',
        );
      },
    );

    test('a page opened outside the app returns before the pause and still gets the grace', () async {
      await setup(after: 0);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      await n.runExternal(() async => true, opensActivity: true);
      wait(const Duration(milliseconds: 100));
      n.paused();
      wait(const Duration(seconds: 30));
      n.resumed();
      await n.settled;
      expect(c.read(lockedProvider), isFalse);
    });
  });

  test('turning the lock on or off at runtime is seen straight away', () async {
    await setup(lockOn: false);
    expect(c.read(lockedProvider), isFalse);
    await lock.setPin('1234');
    await c
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(lockOn: true));
    final n = c.read(lockedProvider.notifier);
    n.paused();
    now = now.add(const Duration(minutes: 5));
    n.resumed();
    expect(c.read(lockedProvider), isTrue);
  });
}
