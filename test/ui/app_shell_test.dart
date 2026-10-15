import 'dart:async';

import 'package:daily_tracker/app.dart';
import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/cloud_backup.dart';
import 'package:daily_tracker/services/lock.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/services/updater.dart';
import 'package:daily_tracker/state/lock_controller.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/ui/screens/habit_detail_screen.dart';
import 'package:daily_tracker/ui/screens/habit_edit_screen.dart';
import 'package:daily_tracker/ui/screens/lock_screen.dart';
import 'package:daily_tracker/ui/screens/progress_screen.dart';
import 'package:daily_tracker/ui/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_drive.dart';
import '../services/lock_test.dart' show FakeBiometrics;
import 'harness.dart';

/// A notification system the test can tap.
final class _TappableNotifications implements ReminderScheduler {
  final _taps = StreamController<String>.broadcast();

  void tap(String payload) => _taps.add(payload);

  @override
  Future<void> init() async {}
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> replaceAll(
    List<PlannedReminder> plan, {
    bool Function(String? payload)? keepSnooze,
  }) async {}
  @override
  Stream<String> get taps => _taps.stream;
  @override
  Future<String?> launchPayload() async => null;
}

final class _Network implements NetworkInfo {
  bool online = false;
  @override
  Future<bool> isOnline() async => online;
  @override
  Future<bool> isOnWifi() async => online;
}

final class _Updates extends Fake implements UpdateService {
  UpdateCheck result = const UpToDate();
  Completer<UpdateCheck>? hold;
  int checks = 0;

  @override
  Future<UpdateCheck> check() {
    checks++;
    return hold?.future ?? Future.value(result);
  }
}

const _release = ReleaseInfo(
  version: '9.9.9',
  notes: 'Better',
  apkUrl: 'https://example.com/a.apk',
);

/// The whole app, [DailyTrackerApp], with fakes only at its edges: an in-memory
/// database, notifications the test taps, no network unless asked, and a lock
/// that the phone lock (always right here) opens.
final class _App {
  _App(this.tester);
  final WidgetTester tester;

  var now = DateTime(2026, 10, 11, 9);

  /// Time since boot; unknown (null) unless a test sets it.
  Future<Duration?> Function() boot = () async => null;
  final notifications = _TappableNotifications();
  final network = _Network();
  final updates = _Updates();
  final bio = FakeBiometrics()..available = false;
  final secureCalls = <bool>[];
  var appExits = 0;
  late Database db;
  late SharedPreferences prefs;

  ProviderContainer get container => ProviderScope.containerOf(
    tester.element(find.byType(DailyTrackerApp).first),
  );

  Future<void> pump({
    bool lockOn = false,
    int lockAfter = 60,
    Widget app = const DailyTrackerApp(),
  }) async {
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('daily_tracker/platform'),
      (call) async {
        if (call.method == 'setSecure') {
          secureCalls.add(call.arguments['secure'] as bool);
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') appExits++;
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(
          const MethodChannel('daily_tracker/platform'),
          null,
        )
        ..setMockMethodCallHandler(SystemChannels.platform, null);
    });
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lockOn': lockOn,
      'lockAfterSeconds': lockAfter,
      // Any stored PIN: these tests open the lock with the phone lock.
      if (lockOn) ...{'lock.salt': 's', 'lock.hash': 'h'},
    });
    prefs = await SharedPreferences.getInstance();
    db = await openAppDatabase(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          elapsedRealtimeProvider.overrideWithValue(() => boot()),
          reminderSchedulerProvider.overrideWithValue(notifications),
          photoStoreProvider.overrideWithValue(NoPhotos()),
          lockServiceProvider.overrideWithValue(
            LockService(
              prefs: prefs,
              biometrics: bio,
              now: () => now,
              elapsed: () => boot(),
            ),
          ),
          appVersionProvider.overrideWith((ref) async => '2.0.0'),
          ledgerProvider.overrideWith((ref) async => sampleLedger()),
          driveAuthProvider.overrideWithValue(FakeAuth(signedIn: false)),
          networkProvider.overrideWithValue(network),
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('', 500)),
          ),
          updateServiceProvider.overrideWithValue(updates),
        ],
        child: app,
      ),
    );
    await settle();
  }

  /// Lets futures resolve and short animations end, without running into the
  /// app's own timers (the update offer waits seconds).
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> background() async {
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await settle();
  }

  Future<void> foreground() async {
    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await settle();
  }

  Future<void> unlock() async {
    await container.read(lockedProvider.notifier).unlockWithDeviceCredential();
    await settle();
  }

  Future<Set<DayKey>> seenDays() => HabitRepository(db).seenDays();
}

void main() {
  setUpAll(loadAppFont);

  group('a notification tap', () {
    testWidgets('opens the habit, and a tap for today pins no day', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
      expect(app.container.read(selectedDayProvider), isNull);

      app.notifications.tap('habit:run@2026-10-09');
      await app.settle();
      expect(app.container.read(selectedDayProvider), DayKey(2026, 10, 9));
    });

    testWidgets('after a late midnight timer still counts today as today', (
      tester,
    ) async {
      final app = _App(tester)..now = DateTime(2026, 10, 12, 22);
      await app.pump();
      // Tuesday morning; the Dart midnight timer has not run (it does not
      // count deep sleep), so the app still thinks it is Monday.
      app.now = DateTime(2026, 10, 13, 7, 5);
      app.notifications.tap('habit:run@2026-10-13');
      await app.settle();
      expect(
        app.container.read(selectedDayProvider),
        isNull,
        reason: 'a pinned day stops the Today screen following midnight',
      );
    });

    testWidgets('keeps a half-typed new habit: the habit opens above it', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.bySemanticsLabel('Add a habit'));
      await app.settle();
      await tester.enterText(find.byType(TextField).first, 'Half-typed habit');
      await app.settle();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.byType(HabitEditScreen), findsOneWidget);
      expect(find.text('Half-typed habit'), findsOneWidget);
    });

    testWidgets('a second tap keeps the half-typed habit below the habit', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.bySemanticsLabel('Add a habit'));
      await app.settle();
      await tester.enterText(find.byType(TextField).first, 'Half-typed habit');
      await app.settle();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      expect(find.byType(HabitEditScreen, skipOffstage: false), findsOneWidget);
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.text('Half-typed habit'), findsOneWidget);
    });

    testWidgets('three taps for the open habit leave one habit page', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.bySemanticsLabel('Add a habit'));
      await app.settle();
      await tester.enterText(find.byType(TextField).first, 'Half-typed habit');
      await app.settle();
      for (var i = 0; i < 3; i++) {
        app.notifications.tap('habit:run@2026-10-11');
        await app.settle();
      }
      expect(
        find.byType(HabitDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.text('Half-typed habit'), findsOneWidget);
    });

    testWidgets('a tap for another habit opens it above the first', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.bySemanticsLabel('Add a habit'));
      await app.settle();
      await tester.enterText(find.byType(TextField).first, 'Half-typed habit');
      await app.settle();
      String shown() => tester
          .widget<HabitDetailScreen>(find.byType(HabitDetailScreen))
          .habitId;
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      app.notifications.tap('habit:read@2026-10-11');
      await app.settle();
      expect(shown(), 'read');
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(shown(), 'run');
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.text('Half-typed habit'), findsOneWidget);
    });

    testWidgets('with nothing unsaved goes back to Today below the habit', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.bySemanticsLabel('Add a habit'));
      await app.settle();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.byType(HabitEditScreen), findsNothing);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('taps for two habits with nothing unsaved leave one page', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      final pages = find.byType(HabitDetailScreen, skipOffstage: false);
      for (final id in ['run', 'read', 'run', 'read']) {
        app.notifications.tap('habit:$id@2026-10-11');
        await app.settle();
        expect(pages, findsOneWidget);
        expect(tester.widget<HabitDetailScreen>(pages).habitId, id);
      }
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('the check-in tap goes to Today from a clean habit page', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
      app.notifications.tap('today');
      await app.settle();
      expect(find.byType(HabitDetailScreen, skipOffstage: false), findsNothing);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('the check-in tap goes to Today from Settings', (tester) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.byTooltip('Settings').first);
      await app.settle();
      expect(find.byType(TodayScreen), findsNothing);
      app.notifications.tap('today');
      await app.settle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('the check-in tap keeps a half-typed habit', (tester) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.bySemanticsLabel('Add a habit'));
      await app.settle();
      await tester.enterText(find.byType(TextField).first, 'Half-typed habit');
      await app.settle();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      app.notifications.tap('today');
      await app.settle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.text('Half-typed habit'), findsOneWidget);
    });

    testWidgets('a dialog on a tab\'s own navigator does not hold the tap', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.text('Progress').last);
      await app.settle();
      // The tab keeps it: going to Today loses nothing.
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(ProgressScreen)),
          useRootNavigator: false,
          builder: (_) => const AlertDialog(content: Text('Tab popup')),
        ),
      );
      await app.settle();
      app.notifications.tap('today');
      await app.settle();
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Tab popup'), findsNothing);
    });

    for (final (what, open) in <(String, void Function(BuildContext))>[
      (
        'dialog',
        (context) => unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('Open popup')),
          ),
        ),
      ),
      (
        'sheet',
        (context) => unawaited(
          showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            builder: (_) => const Text('Open popup'),
          ),
        ),
      ),
    ]) {
      testWidgets('an open $what stays below the habit a tap opens', (
        tester,
      ) async {
        final app = _App(tester);
        await app.pump();
        app.notifications.tap('habit:run@2026-10-11');
        await app.settle();
        open(tester.element(find.byType(HabitDetailScreen)));
        await app.settle();
        app.notifications.tap('today');
        await app.settle();
        expect(find.text('Open popup'), findsOneWidget);
        app.notifications.tap('habit:read@2026-10-11');
        await app.settle();
        expect(
          tester
              .widget<HabitDetailScreen>(find.byType(HabitDetailScreen))
              .habitId,
          'read',
        );
        await tester.binding.handlePopRoute();
        await app.settle();
        expect(find.text('Open popup'), findsOneWidget);
      });
    }

    testWidgets('from another tab opens the habit above Today', (tester) async {
      final app = _App(tester);
      await app.pump();
      await tester.tap(find.text('Progress').last);
      await app.settle();
      expect(find.byType(ProgressScreen), findsOneWidget);
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });
  });

  group('a tap that brings the app back', () {
    testWidgets('waits behind the lock when the app was away too long', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump(lockOn: true);
      await app.unlock();
      await app.background();
      app.now = app.now.add(const Duration(minutes: 10));
      // Android delivers the tap (onNewIntent) before onResume.
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      expect(find.byType(HabitDetailScreen), findsNothing);
      await app.foreground();
      expect(app.container.read(lockedProvider), isTrue);
      expect(find.byType(HabitDetailScreen), findsNothing);
      await app.unlock();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
    });

    testWidgets('opens straight away after a short trip', (tester) async {
      final app = _App(tester);
      await app.pump(lockOn: true);
      await app.unlock();
      await app.background();
      app.now = app.now.add(const Duration(seconds: 10));
      app.notifications.tap('habit:run@2026-10-11');
      await app.foreground();
      expect(app.container.read(lockedProvider), isFalse);
      expect(find.byType(HabitDetailScreen), findsOneWidget);
    });

    testWidgets('keeps the app covered until the time since boot is known', (
      tester,
    ) async {
      final app = _App(tester);
      var since = const Duration(hours: 5);
      Completer<Duration?>? asked;
      app.boot = () async => since;
      await app.pump(lockOn: true);
      await app.unlock();
      await app.background();
      // Ten minutes away, but the clock was set back by nine and a half.
      since += const Duration(minutes: 10);
      app.now = app.now.add(const Duration(seconds: 30));
      app.boot = () => (asked = Completer()).future;
      await app.foreground();
      expect(find.byKey(const ValueKey('privacy-cover')), findsOneWidget);
      expect(app.container.read(lockedProvider), isFalse);
      asked!.complete(since);
      await app.settle();
      expect(app.container.read(lockedProvider), isTrue);
      expect(find.byKey(const ValueKey('privacy-cover')), findsNothing);
      expect(find.byType(LockScreen), findsOneWidget);
    });
  });

  group('while locked', () {
    testWidgets('a snackbar from the app does not show on the lock screen', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump(lockOn: true);
      await app.unlock();
      var undone = false;
      final messenger = ScaffoldMessenger.of(
        tester.element(find.text('Today').first),
      );
      void show(String text) => messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
        ),
      );

      show('Deleted Secret habit');
      await app.settle();
      app.container.read(lockedProvider.notifier).lockNow();
      await app.settle();
      // Gone long before its six seconds, after sliding out under the lock.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Deleted Secret habit'), findsNothing);

      show('Deleted Other habit');
      await app.settle();
      final onLock = find.descendant(
        of: find.byType(LockScreen),
        matching: find.text('Undo'),
      );
      expect(onLock, findsNothing);
      expect(undone, isFalse);
    });

    testWidgets('Back leaves the app instead of walking the hidden pages', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump(lockOn: true);
      await app.unlock();
      app.notifications.tap('habit:run@2026-10-11');
      await app.settle();
      app.container.read(lockedProvider.notifier).lockNow();
      await app.settle();
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(app.appExits, 1);
      await app.unlock();
      expect(find.byType(HabitDetailScreen), findsOneWidget);
    });
  });

  group('in the background', () {
    testWidgets('a new day is not marked as seen until the app is open', (
      tester,
    ) async {
      final app = _App(tester)..now = DateTime(2026, 10, 11, 23, 59);
      await app.pump();
      expect(await app.seenDays(), contains(DayKey(2026, 10, 11)));
      await app.background();
      app.now = DateTime(2026, 10, 12, 0, 1);
      app.container.read(todayProvider.notifier).refresh();
      await app.settle();
      expect(await app.seenDays(), isNot(contains(DayKey(2026, 10, 12))));
      await app.foreground();
      expect(await app.seenDays(), contains(DayKey(2026, 10, 12)));
    });

    testWidgets('unlocking from the background marks nothing as seen', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump(lockOn: true);
      await app.background();
      await app.unlock();
      expect(await app.seenDays(), isEmpty);
    });

    testWidgets('an update check that ends in the background offers nothing', (
      tester,
    ) async {
      final app = _App(tester);
      app.network.online = true;
      app.updates.hold = Completer();
      await app.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(app.updates.checks, 1);
      await app.background();
      app.updates.hold!.complete(const UpdateAvailable(_release));
      await app.settle();
      await app.foreground();
      expect(find.text('Skip this version'), findsNothing);
    });
  });

  group('the update offer', () {
    testWidgets('a trip away before the offer is due still gets it later', (
      tester,
    ) async {
      final app = _App(tester);
      app.network.online = true;
      app.updates.result = const UpdateAvailable(_release);
      await app.pump();
      await app.background();
      await tester.pump(const Duration(seconds: 10));
      await app.foreground();
      await tester.pump(const Duration(seconds: 5));
      await app.settle();
      expect(find.text('Skip this version'), findsOneWidget);
    });

    testWidgets(
      'an offer given up in the background is made on the next return',
      (tester) async {
        final app = _App(tester);
        app.network.online = true;
        app.updates.hold = Completer();
        await app.pump();
        await tester.pump(const Duration(seconds: 5));
        await app.background();
        app.updates.hold!.complete(const UpdateAvailable(_release));
        await app.settle();
        await app.foreground();
        expect(find.text('Skip this version'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        await app.settle();
        expect(find.text('Skip this version'), findsOneWidget);
      },
    );
  });

  group('the app lock setting', () {
    testWidgets(
      'closes the keyboard when the app leaves, not when the shade is pulled',
      (tester) async {
        final app = _App(tester);
        await app.pump(lockOn: true);
        await app.unlock();
        await tester.tap(find.bySemanticsLabel('Add a habit'));
        await app.settle();
        await tester.enterText(find.byType(TextField).first, 'Typing');
        bool typing() => tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus;
        expect(typing(), isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await app.settle();
        expect(typing(), isTrue, reason: 'the notification shade only');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await app.settle();
        expect(
          typing(),
          isFalse,
          reason: 'no keyboard in the recent-apps view',
        );
      },
    );

    testWidgets('turns the secure window flag on and off with it', (
      tester,
    ) async {
      final app = _App(tester);
      await app.pump();
      expect(app.secureCalls, [false]);
      await app.container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(lockOn: true));
      await app.settle();
      await app.container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(lockOn: false));
      await app.settle();
      expect(app.secureCalls, [false, true, false]);
    });
  });

  testWidgets('each router gets its own navigator key', (tester) async {
    final a = buildRouter(onboardingDone: () => true);
    final b = buildRouter(onboardingDone: () => true);
    expect(a.routerDelegate.navigatorKey, isNot(b.routerDelegate.navigatorKey));
    // Two apps at once (as when Android builds a second engine) would clash
    // on one shared key.
    await _App(tester).pump(
      app: const Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(child: DailyTrackerApp()),
          Expanded(child: DailyTrackerApp(key: ValueKey('second'))),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
