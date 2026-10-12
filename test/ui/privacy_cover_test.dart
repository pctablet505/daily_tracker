import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:daily_tracker/ui/widgets/privacy_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool enabled}) => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: PrivacyCover(enabled: enabled, child: const Text('my habits')),
);

void main() {
  const cover = ValueKey('privacy-cover');

  testWidgets(
    'with the lock on, leaving the app covers the screen and coming back clears it',
    (tester) async {
      await tester.pumpWidget(_host(enabled: true));
      expect(find.byKey(cover), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(cover), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(cover), findsNothing);
    },
  );

  testWidgets('it stays covered all the way to the background and back', (
    tester,
  ) async {
    await tester.pumpWidget(_host(enabled: true));
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
      expect(find.byKey(cover), findsOneWidget, reason: s.name);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(cover), findsNothing);
  });

  testWidgets('with the lock off the screen is never covered', (tester) async {
    await tester.pumpWidget(_host(enabled: false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byKey(cover), findsNothing);
    expect(find.text('my habits'), findsOneWidget);
  });
}
