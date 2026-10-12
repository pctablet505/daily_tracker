import 'dart:ui' show SemanticsAction;

import 'package:daily_tracker/ui/screens/habits_screen.dart';
import 'package:daily_tracker/ui/screens/progress_screen.dart';
import 'package:daily_tracker/ui/screens/today_screen.dart';
import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'harness.dart';

/// Settings has nothing to do with habits, so it must not be reachable only from the
/// Habits tab: every main screen has a Settings button in its header.
Future<void> _pumpInRouter(
  WidgetTester tester,
  Widget home, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 780) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('SETTINGS PAGE')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: await baseOverrides(ledger: sampleLedger()),
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadAppFont);

  final screens = <String, Widget Function()>{
    'Today': () => const TodayScreen(),
    'Progress': () => const ProgressScreen(),
    'Habits': () => const HabitsScreen(),
  };

  for (final e in screens.entries) {
    testWidgets('${e.key} has a Settings button that opens Settings', (
      tester,
    ) async {
      await _pumpInRouter(tester, e.value());
      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS PAGE'), findsOneWidget);
    });

    testWidgets('${e.key} Settings button is its own screen-reader element', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpInRouter(tester, e.value());
      // An exact label: merged with the screen title it would read "Progress, Settings".
      final gear = find.bySemanticsLabel('Settings');
      expect(gear, findsOneWidget);
      expect(
        tester
            .getSemantics(gear)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('${e.key} keeps its Settings button at double text size', (
      tester,
    ) async {
      final errors = await collectFrameworkErrors(
        () => _pumpInRouter(tester, e.value(), textScale: 2),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
      expect(find.byTooltip('Settings'), findsOneWidget);
    });
  }

  testWidgets(
    'Today gives the whole header to the search field while searching',
    (tester) async {
      await _pumpInRouter(tester, const TodayScreen());
      await tester.tap(find.byTooltip('Search habits'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip('Close search'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsNothing);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip('Settings'), findsOneWidget);
    },
  );
}
