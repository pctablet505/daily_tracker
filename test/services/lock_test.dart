import 'dart:async';
import 'dart:isolate';

import 'package:daily_tracker/services/lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class FakeBiometrics implements Biometrics {
  bool available = true;
  bool result = true;
  bool deviceResult = true;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(
    String reason, {
    required bool biometricOnly,
  }) async {
    asked++;
    return biometricOnly ? result : deviceResult;
  }
}

void main() {
  group('PIN hashing', () {
    test(
      'the same PIN and salt give the same hash; either changing gives another',
      () {
        final a = hashPin('1234', 'salt');
        expect(hashPin('1234', 'salt'), a);
        expect(hashPin('1235', 'salt'), isNot(a));
        expect(hashPin('1234', 'salt2'), isNot(a));
        expect(a.length, 64);
      },
    );

    test('is PBKDF2 with 20,000 rounds: slow enough to make guessing a 4 digit PIN offline costly', () {
      expect(hashPin('1234', 'salt'), pbkdf2Sha256('1234', 'salt', 20000, 32));
      expect(
        hashPin('1234', 'salt'),
        isNot(pbkdf2Sha256('1234', 'salt', 19999, 32)),
      );
    });

    test('matches a known PBKDF2-HMAC-SHA256 vector with many rounds', () {
      expect(
        pbkdf2Sha256('password', 'salt', 4096, 32),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('matches a known PBKDF2-HMAC-SHA256 vector (so the hash is the real thing)', () {
      // RFC 7914 section 11 gives PBKDF2-HMAC-SHA-256("passwd", "salt", c=1, dkLen=64); its first 32 bytes:
      expect(
        pbkdf2Sha256('passwd', 'salt', 1, 32),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
      );
    });

    test('a salt is random per PIN', () {
      expect(newSalt(), isNot(newSalt()));
      expect(newSalt().length, greaterThanOrEqualTo(16));
    });
  });

  group('wrong-guess back-off', () {
    for (final c in <(int, Duration)>[
      (0, Duration.zero),
      (4, Duration.zero),
      (5, Duration(seconds: 30)),
      (6, Duration(minutes: 1)),
      (7, Duration(minutes: 5)),
      (8, Duration(minutes: 15)),
      (9, Duration(hours: 1)),
      (30, Duration(hours: 1)),
    ]) {
      test(
        '${c.$1} wrong guesses wait ${c.$2}',
        () => expect(backoffFor(c.$1), c.$2),
      );
    }
  });

  group('locking after time away', () {
    final t = DateTime(2026, 10, 11, 12);
    test('locks when the app was away longer than the setting', () {
      expect(
        shouldLock(awayFor: const Duration(seconds: 61), lockAfterSeconds: 60),
        isTrue,
      );
      expect(
        shouldLock(awayFor: const Duration(seconds: 60), lockAfterSeconds: 60),
        isTrue,
        reason: 'at the limit counts as away',
      );
      expect(
        shouldLock(awayFor: const Duration(seconds: 59), lockAfterSeconds: 60),
        isFalse,
      );
    });

    test('immediately means any time away', () {
      expect(shouldLock(awayFor: Duration.zero, lockAfterSeconds: 0), isTrue);
      expect(
        shouldLock(
          awayFor: const Duration(milliseconds: 5),
          lockAfterSeconds: 0,
        ),
        isTrue,
      );
    });

    test('a clock that moved backwards locks', () {
      expect(
        shouldLock(
          awayFor: t.difference(t.add(const Duration(hours: 1))),
          lockAfterSeconds: 300,
        ),
        isTrue,
      );
    });
  });

  group('the lock', () {
    late SharedPreferences prefs;
    late FakeBiometrics bio;
    late LockService lock;
    var now = DateTime(2026, 10, 11, 12);
    Duration? boot = const Duration(hours: 5);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      bio = FakeBiometrics();
      now = DateTime(2026, 10, 11, 12);
      boot = const Duration(hours: 5);
      lock = LockService(
        prefs: prefs,
        biometrics: bio,
        now: () => now,
        elapsed: () async => boot,
      );
    });

    Future<void> fiveWrong() async {
      await lock.setPin('1234');
      for (var i = 0; i < 5; i++) {
        await lock.checkPin('0000');
      }
    }

    test('has no PIN at first', () {
      expect(lock.hasPin, isFalse);
    });

    test('a PIN of 4 to 6 digits can be set; others are refused', () async {
      for (final bad in ['', '123', '1234567', 'abcd', '12 34', '12.4']) {
        expect(() => lock.setPin(bad), throwsArgumentError, reason: bad);
      }
      for (final good in ['1234', '12345', '123456', '0000']) {
        await lock.setPin(good);
        expect(lock.hasPin, isTrue);
      }
    });

    test('the PIN is stored hashed, not as typed', () async {
      await lock.setPin('4821');
      final stored = prefs
          .getKeys()
          .map((k) => prefs.get(k).toString())
          .join(' ');
      expect(stored.contains('4821'), isFalse);
    });

    test('the right PIN unlocks, a wrong one does not', () async {
      await lock.setPin('1234');
      expect((await lock.checkPin('1234')).ok, isTrue);
      final bad = await lock.checkPin('9999');
      expect(bad.ok, isFalse);
      expect(bad.failures, 1);
    });

    test(
      'five wrong guesses lock out for 30 seconds, even the right PIN',
      () async {
        await lock.setPin('1234');
        for (var i = 0; i < 4; i++) {
          expect((await lock.checkPin('0000')).waitFor, Duration.zero);
        }
        final fifth = await lock.checkPin('0000');
        expect(fifth.ok, isFalse);
        expect(fifth.failures, 5);
        expect(fifth.waitFor, const Duration(seconds: 30));
        expect(lock.remainingWait, const Duration(seconds: 30));
        final during = await lock.checkPin('1234');
        expect(during.ok, isFalse);
        expect(during.waitFor, const Duration(seconds: 30));
        now = now.add(const Duration(seconds: 31));
        boot = boot! + const Duration(seconds: 31);
        expect(lock.remainingWait, Duration.zero);
        expect((await lock.checkPin('1234')).ok, isTrue);
      },
    );

    test('a right PIN resets the count', () async {
      await lock.setPin('1234');
      await lock.checkPin('0');
      await lock.checkPin('1111');
      await lock.checkPin('1234');
      expect((await lock.checkPin('2222')).failures, 1);
    });

    test('the wrong-guess count survives restarting the app', () async {
      await lock.setPin('1234');
      for (var i = 0; i < 5; i++) {
        await lock.checkPin('0000');
      }
      final again = LockService(prefs: prefs, biometrics: bio, now: () => now);
      expect((await again.checkPin('1234')).waitFor, isNot(Duration.zero));
    });

    test('removing the PIN forgets it', () async {
      await lock.setPin('1234');
      await lock.clearPin();
      expect(lock.hasPin, isFalse);
    });

    test('fingerprint works only when the phone has one set up', () async {
      expect(await lock.unlockWithBiometrics(), isTrue);
      bio.result = false;
      expect(await lock.unlockWithBiometrics(), isFalse);
      bio.available = false;
      bio.result = true;
      final before = bio.asked;
      expect(await lock.unlockWithBiometrics(), isFalse);
      expect(bio.asked, before, reason: 'not even asked');
    });

    test(
      'the phone screen lock is a way back in when the PIN is forgotten',
      () async {
        bio.deviceResult = true;
        expect(await lock.unlockWithDeviceCredential(), isTrue);
        bio.deviceResult = false;
        expect(await lock.unlockWithDeviceCredential(), isFalse);
      },
    );

    test(
      'unlocking with biometrics or phone lock resets the wrong-guess backoff',
      () async {
        await lock.setPin('1234');
        for (var i = 0; i < 5; i++) {
          await lock.checkPin('0000');
        }
        expect(lock.remainingWait, const Duration(seconds: 30));
        expect(await lock.unlockWithDeviceCredential(), isTrue);
        expect(lock.remainingWait, Duration.zero);
        expect((await lock.checkPin('0000')).failures, 1);
      },
    );

    test(
      'a backward clock jump cannot stretch the backoff beyond its cap',
      () async {
        await lock.setPin('1234');
        for (var i = 0; i < 5; i++) {
          await lock.checkPin('0000');
        }
        now = now.subtract(const Duration(days: 365));
        expect(lock.remainingWait, const Duration(seconds: 30));
      },
    );

    test('moving the clock forward does not end the wrong-PIN wait', () async {
      await fiveWrong();
      now = now.add(const Duration(days: 1));
      final r = await lock.checkPin('1234');
      expect(r.ok, isFalse);
      expect(r.waitFor, const Duration(seconds: 30));
    });

    test('the wait ends once its time has really passed', () async {
      await fiveWrong();
      now = now.add(const Duration(seconds: 31));
      boot = boot! + const Duration(seconds: 31);
      expect((await lock.checkPin('1234')).ok, isTrue);
    });

    test(
      'after the phone restarts the wall clock alone times the wait',
      () async {
        await fiveWrong();
        boot = const Duration(seconds: 10);
        now = now.add(const Duration(seconds: 10));
        expect(await lock.waitLeft(), const Duration(seconds: 20));
        expect(prefs.getKeys(), isNot(contains('lock.untilBoot')));
        boot = boot! + const Duration(seconds: 21);
        now = now.add(const Duration(seconds: 21));
        expect(await lock.waitLeft(), Duration.zero);
      },
    );

    test(
      'a wait that ended days ago does not come back after a restart',
      () async {
        await fiveWrong();
        now = now.add(const Duration(days: 2));
        boot = const Duration(minutes: 3);
        expect(await lock.waitLeft(), Duration.zero);
        expect((await lock.checkPin('1234')).ok, isTrue);
      },
    );

    test(
      'without the boot clock the wall clock alone times the wait',
      () async {
        boot = null;
        await fiveWrong();
        expect(await lock.waitLeft(), const Duration(seconds: 30));
        now = now.add(const Duration(seconds: 31));
        expect((await lock.checkPin('1234')).ok, isTrue);
      },
    );

    test('guesses sent together are checked in turn: the fifth starts the wait, the sixth is refused', () async {
      await lock.setPin('1234');
      for (var i = 0; i < 4; i++) {
        await lock.checkPin('0000');
      }
      final r = await Future.wait([
        for (final g in ['1111', '2222', '1234']) lock.checkPin(g),
      ]);
      expect(r[0].failures, 5);
      expect(r[0].waitFor, const Duration(seconds: 30));
      expect(r[1].waitFor, const Duration(seconds: 30));
      expect(r[2].ok, isFalse);
      expect(r[2].waitFor, const Duration(seconds: 30));
    });

    test('salt and hash are stored as one value, so a kill mid-way cannot split them', () async {
      await lock.setPin('1234');
      expect(prefs.getKeys(), containsAll(['lock.pin']));
      expect(prefs.getKeys(), isNot(contains('lock.salt')));
      expect(prefs.getKeys(), isNot(contains('lock.hash')));
    });

    test(
      'a PIN stored by an older version (salt and hash apart) still works',
      () async {
        await prefs.setString('lock.salt', 'old-salt');
        await prefs.setString('lock.hash', hashPin('2468', 'old-salt'));
        expect(lock.hasPin, isTrue);
        expect((await lock.checkPin('1357')).ok, isFalse);
        expect((await lock.checkPin('2468')).ok, isTrue);
      },
    );

    test('a change of PIN cut short after the new value is written uses the new PIN', () async {
      await prefs.setString('lock.salt', 'old-salt');
      await prefs.setString('lock.hash', hashPin('2468', 'old-salt'));
      await prefs.setString(
        'lock.pin',
        'new-salt:${hashPin('1357', 'new-salt')}',
      );
      expect((await lock.checkPin('2468')).ok, isFalse);
      expect((await lock.checkPin('1357')).ok, isTrue);
    });

    test(
      'setting and checking a PIN leave the UI isolate free while hashing',
      () async {
        var timerRan = false;
        Timer.run(() => timerRan = true);
        await lock.setPin('1234');
        expect(timerRan, isTrue, reason: 'setPin hashed without yielding');
        timerRan = false;
        Timer.run(() => timerRan = true);
        await lock.checkPin('1234');
        expect(timerRan, isTrue, reason: 'checkPin hashed without yielding');
      },
    );

    test('setting and checking a PIN hash on the background runner', () async {
      var runs = 0;
      final counted = LockService(
        prefs: prefs,
        biometrics: bio,
        now: () => now,
        elapsed: () async => boot,
        runHash: (hash) {
          runs++;
          return Isolate.run(hash);
        },
      );
      await counted.setPin('1234');
      expect(runs, 1);
      expect((await counted.checkPin('1234')).ok, isTrue);
      expect(runs, 2);
    });
  });
}
