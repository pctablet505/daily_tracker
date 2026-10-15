import 'dart:async';

import 'package:daily_tracker/services/lock.dart';
import 'package:daily_tracker/state/lock_controller.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/ui/screens/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// The phone's own prompts, held open until the test answers them.
final class _HeldPrompts implements Biometrics {
  int asked = 0;
  Completer<bool>? open;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate(String reason, {required bool biometricOnly}) {
    asked++;
    return (open = Completer<bool>()).future;
  }
}

const _phoneLock = 'Forgot PIN? Use phone lock';

void main() {
  setUpAll(loadAppFont);

  late DateTime now;
  late _HeldPrompts prompts;

  Future<void> pump(
    WidgetTester tester, {
    bool fingerprintOn = true,
    bool credentialOnly = true,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lockOn': true,
      'lockBiometric': fingerprintOn,
      'lock.salt': 's',
      'lock.hash': 'h',
      ...prefs,
    });
    final sp = await SharedPreferences.getInstance();
    await pumpScreen(
      tester,
      const LockScreen(),
      overrides: [
        sharedPrefsProvider.overrideWithValue(sp),
        clockProvider.overrideWithValue(() => now),
        elapsedRealtimeProvider.overrideWithValue(() async => null),
        lockServiceProvider.overrideWithValue(
          LockService(
            prefs: sp,
            biometrics: prompts,
            now: () => now,
            elapsed: () async => null,
          ),
        ),
        phoneLockCredentialOnlyProvider.overrideWith(
          (ref) async => credentialOnly,
        ),
      ],
    );
  }

  setUp(() {
    now = DateTime(2026, 10, 11, 12);
    prompts = _HeldPrompts();
  });

  group('"Use phone lock"', () {
    testWidgets('is offered where the phone lock prompt takes no fingerprint', (
      tester,
    ) async {
      await pump(tester, fingerprintOn: false);
      expect(find.text(_phoneLock), findsOneWidget);
    });

    testWidgets(
      'is hidden with fingerprint unlock off where the phone lock prompt also takes a fingerprint',
      (tester) async {
        await pump(tester, fingerprintOn: false, credentialOnly: false);
        expect(find.text(_phoneLock), findsNothing);
      },
    );

    testWidgets('is offered with fingerprint unlock on, on any phone', (
      tester,
    ) async {
      await pump(tester, credentialOnly: false);
      expect(find.text(_phoneLock), findsOneWidget);
    });

    testWidgets('a second tap while the prompt is up is ignored', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text(_phoneLock));
      await tester.pump();
      await tester.tap(find.text(_phoneLock));
      await tester.pump();
      expect(prompts.asked, 1);
      prompts.open!.complete(false);
      await tester.pump();
      expect(
        find.text('Could not unlock with your phone lock.'),
        findsOneWidget,
      );
      await tester.tap(find.text(_phoneLock));
      await tester.pump();
      expect(prompts.asked, 2, reason: 'a new try once the first one ended');
    });
  });

  group('the wrong-PIN wait', () {
    Map<String, Object> waitUntil(Duration d) => {
      'lock.failures': 5,
      'lock.until': now.add(d).millisecondsSinceEpoch,
    };

    testWidgets('rounds part of a second up, never showing "Wait 0 s"', (
      tester,
    ) async {
      await pump(
        tester,
        prefs: waitUntil(const Duration(seconds: 29, milliseconds: 500)),
      );
      expect(find.text('Too many tries. Wait 30 s.'), findsOneWidget);
      now = now.add(const Duration(seconds: 29));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Too many tries. Wait 1 s.'), findsOneWidget);
    });

    testWidgets('follows the clock rather than counting ticks', (tester) async {
      await pump(tester, prefs: waitUntil(const Duration(seconds: 30)));
      // Time the ticks did not see: the screen was off or the app was away.
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Too many tries. Wait 10 s.'), findsOneWidget);
    });

    testWidgets('is over at once when the app comes back after it ended', (
      tester,
    ) async {
      await pump(tester, prefs: waitUntil(const Duration(seconds: 30)));
      now = now.add(const Duration(seconds: 40));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Too many tries'), findsNothing);
    });
  });
}
