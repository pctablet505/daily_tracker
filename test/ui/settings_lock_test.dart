import 'package:daily_tracker/state/lock_controller.dart';
import 'package:daily_tracker/ui/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _phoneLock = 'Forgot PIN? Use phone lock';

void main() {
  setUpAll(loadAppFont);

  Future<void> pump(
    WidgetTester tester, {
    required bool fingerprintOn,
    required bool credentialOnly,
  }) async {
    final o = await baseOverrides(
      ledger: sampleLedger(),
      prefs: {
        'lockOn': true,
        'lockBiometric': fingerprintOn,
        'lock.salt': 's',
        'lock.hash': 'h',
      },
    );
    await pumpScreen(
      tester,
      const SettingsScreen(),
      overrides: [
        ...o,
        phoneLockCredentialOnlyProvider.overrideWith(
          (ref) async => credentialOnly,
        ),
      ],
    );
  }

  Future<void> open(WidgetTester tester, String row) async {
    final finder = find.text(row, skipOffstage: false);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the App lock note says a forgotten PIN on an older phone with fingerprint off means clearing data',
    (tester) async {
      await pump(tester, fingerprintOn: true, credentialOnly: true);
      expect(
        find.text(
          'If you forget the PIN and have no phone screen lock, the only way back is clearing the app\'s data.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'On Android 10 and older with "Use fingerprint" off, the phone lock is not offered either, so a forgotten PIN means clearing the app\'s data.',
        ),
        findsOneWidget,
      );
    },
  );

  group('the PIN sheet in Settings', () {
    testWidgets(
      'hides "Use phone lock" with fingerprint unlock off where the phone lock prompt also takes a fingerprint',
      (tester) async {
        await pump(tester, fingerprintOn: false, credentialOnly: false);
        await open(tester, 'Change PIN');
        expect(find.text('Enter your current PIN'), findsOneWidget);
        expect(find.text(_phoneLock), findsNothing);
      },
    );

    testWidgets('hides it too when turning the lock off', (tester) async {
      await pump(tester, fingerprintOn: false, credentialOnly: false);
      await open(tester, 'App lock');
      expect(find.text('Enter your PIN to turn the lock off'), findsOneWidget);
      expect(find.text(_phoneLock), findsNothing);
    });

    testWidgets('offers it where the phone lock prompt takes no fingerprint', (
      tester,
    ) async {
      await pump(tester, fingerprintOn: false, credentialOnly: true);
      await open(tester, 'Change PIN');
      expect(find.text(_phoneLock), findsOneWidget);
    });

    testWidgets('offers it with fingerprint unlock on, on any phone', (
      tester,
    ) async {
      await pump(tester, fingerprintOn: true, credentialOnly: false);
      await open(tester, 'Change PIN');
      expect(find.text(_phoneLock), findsOneWidget);
    });
  });
}
