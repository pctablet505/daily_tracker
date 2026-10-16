import 'dart:async';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/state/actions.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/ui/screens/onboarding_screen.dart';
import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'harness.dart';

final class _CountingNotifications implements ReminderScheduler {
  int asked = 0;

  /// When set, the permission dialog stays open until it completes.
  Completer<bool>? answer;
  @override
  Future<void> init() async {}
  @override
  Future<bool> hasPermission() async => asked > 0;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return answer?.future ?? true;
  }

  @override
  Future<void> replaceAll(
    List<PlannedReminder> plan, {
    bool Function(String? payload)? keepSnooze,
  }) async {}
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> launchPayload() async => null;
}

void main() {
  sqfliteFfiInit();
  setUpAll(loadAppFont);

  late Database db;
  late ProviderContainer container;
  late _CountingNotifications notifications;
  late int changes;

  /// Opens the first-run screen over a real in-memory database, picks two
  /// habits and goes on to the notifications step.
  Future<void> pickTwoAndGoOn(WidgetTester tester) async {
    db = (await tester.runAsync(
      () => openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
        singleInstance: false,
      ),
    ))!;
    addTearDown(() => tester.runAsync(db.close));
    notifications = _CountingNotifications();
    changes = 0;
    var ids = 0;
    final overrides = (await baseOverrides(prefs: {'onboardingDone': false}))
      // The harness's unused database and silent notifications.
      ..removeAt(3)
      ..removeAt(0)
      ..add(databaseProvider.overrideWithValue(db))
      ..add(reminderSchedulerProvider.overrideWithValue(notifications))
      ..add(
        actionsProvider.overrideWithValue(
          HabitActions(
            repo: HabitRepository(db, onChanged: () => changes++),
            photos: NoPhotos(),
            now: DateTime.now,
            newId: () => 'id${ids++}',
          ),
        ),
      );
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
      ],
    );
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(
              theme: buildTheme(Brightness.light),
              routerConfig: router,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exercise'));
    await tester.tap(find.text('Read'));
    await tester.pump();
    await tester.tap(find.text('Start with 2 habits'));
    await tester.pumpAndSettle();
    expect(find.text('Want a nudge?'), findsOneWidget);
  }

  /// Database writes need real time: lets them finish, then settles.
  Future<void> untilHome(WidgetTester tester) async {
    for (var i = 0; i < 20 && find.text('HOME').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'Skip on the notifications step keeps the picked habits and asks for nothing',
    (tester) async {
      await pickTwoAndGoOn(tester);
      await tester.tap(find.text('Skip'));
      await untilHome(tester);

      expect(find.text('HOME'), findsOneWidget);
      expect(container.read(settingsProvider).onboardingDone, isTrue);
      final saved = (await tester.runAsync(
        () => HabitRepository(db).habits(),
      ))!;
      expect(saved.map((h) => h.name), unorderedEquals(['Exercise', 'Read']));
      expect(notifications.asked, 0);
      expect(changes, 1, reason: 'the picked habits are added in one go');
    },
  );

  testWidgets(
    'Back on the notifications step returns to the picker with the picks kept',
    (tester) async {
      await pickTwoAndGoOn(tester);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('What will you do every day?'), findsOneWidget);
      expect(find.text('Start with 2 habits'), findsOneWidget);
    },
  );

  /// Records the platform calls, so a test can see the app being closed.
  List<String> watchPlatform(WidgetTester tester) {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  testWidgets(
    'system Back on the notifications step returns to the picker with the picks kept',
    (tester) async {
      await pickTwoAndGoOn(tester);
      final calls = watchPlatform(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(find.text('What will you do every day?'), findsOneWidget);
      expect(find.text('Start with 2 habits'), findsOneWidget);
    },
  );

  testWidgets('system Back while the habits are being added does nothing', (
    tester,
  ) async {
    await pickTwoAndGoOn(tester);
    notifications.answer = Completer();
    await tester.tap(find.text('Allow notifications'));
    await tester.pump();
    final calls = watchPlatform(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(calls, isNot(contains('SystemNavigator.pop')));
    expect(find.text('Want a nudge?'), findsOneWidget);
    notifications.answer!.complete(true);
    await untilHome(tester);
    expect(find.text('HOME'), findsOneWidget);
  });
}
