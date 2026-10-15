import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'logic/habit_form.dart';
import 'services/reminder_plan.dart';
import 'services/reminder_sync.dart';
import 'state/external_changes.dart';
import 'state/lock_controller.dart';
import 'state/providers.dart';
import 'state/services.dart';
import 'state/settings.dart';
import 'state/update_prompt.dart';
import 'ui/screens/backup_screen.dart';
import 'ui/screens/habit_detail_screen.dart';
import 'ui/screens/habit_edit_screen.dart';
import 'ui/screens/habits_screen.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/packs_screen.dart';
import 'ui/screens/progress_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/today_screen.dart';
import 'ui/root_routes.dart';
import 'ui/shell.dart';
import 'ui/sheets/update_sheet.dart';
import 'ui/theme/theme.dart';
import 'ui/widgets/privacy_cover.dart';

const _platformChannel = MethodChannel('daily_tracker/platform');

GoRouter buildRouter({
  required bool Function() onboardingDone,
  String initialLocation = '/',
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver>? observers,
}) {
  final rootKey = navigatorKey ?? GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    observers: observers,
    initialLocation: initialLocation,
    redirect: (context, state) {
      if (!onboardingDone() && state.matchedLocation != '/onboarding')
        return '/onboarding';
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const TodayScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/progress',
                builder: (_, _) => const ProgressScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/habits', builder: (_, _) => const HabitsScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/habits/packs',
        parentNavigatorKey: rootKey,
        builder: (_, s) => PacksScreen(
          openId: s.uri.queryParameters['open'],
          import: s.uri.queryParameters['import'] == '1',
        ),
      ),
      GoRoute(
        path: '/habit/new',
        parentNavigatorKey: rootKey,
        builder: (_, s) => HabitEditScreen(
          preset: s.extra is HabitForm ? s.extra! as HabitForm : null,
        ),
      ),
      GoRoute(
        path: '/habit/:id',
        parentNavigatorKey: rootKey,
        builder: (_, s) => HabitDetailScreen(habitId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/habit/:id/edit',
        parentNavigatorKey: rootKey,
        builder: (_, s) => HabitEditScreen(habitId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/backup',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const BackupScreen(),
      ),
    ],
  );
}

class DailyTrackerApp extends ConsumerStatefulWidget {
  const DailyTrackerApp({super.key});

  @override
  ConsumerState<DailyTrackerApp> createState() => _DailyTrackerAppState();
}

class _DailyTrackerAppState extends ConsumerState<DailyTrackerApp>
    with WidgetsBindingObserver {
  final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _rootRoutes = RootRoutes();
  late final GoRouter _router = buildRouter(
    onboardingDone: () => ref.read(settingsProvider).onboardingDone,
    navigatorKey: _rootKey,
    observers: [_rootRoutes],
  );
  StreamSubscription<String>? _taps;
  Timer? _updateTimer;
  bool _offeringUpdate = false;
  bool _inForeground = true;
  String? _pendingPayload;

  /// Set from "resumed" until the lock has decided whether to lock (it asks the
  /// phone for the time since boot): the app stays covered and taps wait.
  Future<void>? _lockCheck;
  late final UpdatePrompter _prompter = UpdatePrompter(
    prefs: ref.read(sharedPrefsProvider),
    now: ref.read(clockProvider),
    check: () => ref.read(updateServiceProvider).check(),
    isOnWifi: () => ref.read(networkProvider).isOnWifi(),
    isOnline: () => ref.read(networkProvider).isOnline(),
    wifiOnly: () => ref.read(settingsProvider).wifiOnlyUpdate,
  );

  void _scheduleUpdateOffer(Duration delay) {
    _updateTimer?.cancel();
    _updateTimer = Timer(delay, () => unawaited(_offerUpdate()));
  }

  Future<void> _syncSecureWindow(bool secure) async {
    try {
      await _platformChannel.invokeMethod<void>('setSecure', {
        'secure': secure,
      });
    } catch (_) {
      // Ignored in tests or on platforms without the channel.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scheduler = ref.read(reminderSchedulerProvider);
    _taps = scheduler.taps.listen(_openPayload);
    unawaited(
      scheduler.launchPayload().then((p) {
        if (mounted && p != null) _openPayload(p);
      }),
    );
    unawaited(ref.read(cloudBackupProvider).restoreSession());
    unawaited(_syncSecureWindow(ref.read(settingsProvider).lockOn));
    if (ref.read(lockedProvider)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => FocusManager.instance.primaryFocus?.unfocus(),
      );
    }
    ref.listenManual(
      settingsProvider.select((s) => s.lockOn),
      (_, now) => unawaited(_syncSecureWindow(now)),
    );
    // An update offer is held back while locked; offer it once the user is in.
    ref.listenManual(lockedProvider, (was, now) {
      if (now) {
        _updateTimer?.cancel();
        FocusManager.instance.primaryFocus?.unfocus();
        // A snackbar can name a habit, and its Undo must not work while locked.
        _messengerKey.currentState?.clearSnackBars();
      } else if (was == true) {
        if (ref.read(settingsProvider).onboardingDone) {
          if (_inForeground) {
            unawaited(
              ref.read(actionsProvider).markSeen(ref.read(todayProvider)),
            );
          }
          unawaited(ref.read(cloudBackupProvider).autoBackupIfDue());
        }
        _openPendingPayload();
        if (_inForeground) _scheduleUpdateOffer(const Duration(seconds: 2));
      }
    });
    ref.listenManual(settingsProvider.select((s) => s.onboardingDone), (
      was,
      now,
    ) {
      if (was == false && now && _inForeground && !ref.read(lockedProvider)) {
        unawaited(ref.read(actionsProvider).markSeen(ref.read(todayProvider)));
      }
    });
    ref.listenManual(todayProvider, (was, now) {
      if (was != null && was != now) {
        if (_inForeground &&
            ref.read(settingsProvider).onboardingDone &&
            !ref.read(lockedProvider)) {
          unawaited(ref.read(actionsProvider).markSeen(now));
        }
        unawaited(ref.read(reminderSyncProvider).resync());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onForeground();
      _scheduleUpdateOffer(const Duration(seconds: 4));
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_taps?.cancel());
    super.dispose();
  }

  void _openPayload(String payload) {
    if (!ref.read(settingsProvider).onboardingDone) return;
    // A tap brings the app back before "resumed" has run the lock check.
    if (!_inForeground || _lockCheck != null || ref.read(lockedProvider)) {
      _pendingPayload = payload;
      return;
    }
    // The midnight timer runs late after deep sleep.
    ref.read(todayProvider.notifier).refresh();
    final habit = parseHabitPayload(payload);
    final keepPages = _wouldLoseSomething();
    if (habit != null) {
      final today = ref.read(todayProvider);
      ref
          .read(selectedDayProvider.notifier)
          .select(habit.day == null || habit.day == today ? null : habit.day);
      if (!keepPages) {
        _router.go('/');
      } else if (_showsHabit(habit.habitId)) {
        return;
      }
      unawaited(_router.push('/habit/${Uri.encodeComponent(habit.habitId)}'));
    } else {
      ref.read(selectedDayProvider.notifier).select(null);
      if (!keepPages) _router.go('/');
    }
  }

  void _openPendingPayload() {
    final pending = _pendingPayload;
    _pendingPayload = null;
    if (pending != null) _openPayload(pending);
  }

  /// Whether replacing the pages would drop a dialog, a sheet or a page that
  /// refuses Back (an unsaved form). An earlier tap can have opened a habit
  /// above the form, so every route counts, not only the top one; a tap then
  /// opens its page on top instead.
  bool _wouldLoseSomething() => _rootRoutes.wouldLoseSomething;

  /// Whether the top page is this habit's page; a second one would only stack up.
  bool _showsHabit(String id) {
    final top = _router.state;
    return top.fullPath == '/habit/:id' && top.pathParameters['id'] == id;
  }

  void _waitForLockCheck() {
    final check = ref.read(lockedProvider.notifier).settled;
    setState(() {
      _lockCheck = check;
    });
    unawaited(
      check.whenComplete(() {
        if (!mounted || !identical(_lockCheck, check)) return;
        setState(() => _lockCheck = null);
        // Locked: unlocking opens the tap and offers the update instead.
        if (!_inForeground || ref.read(lockedProvider)) return;
        _openPendingPayload();
        _scheduleUpdateOffer(const Duration(seconds: 2));
      }),
    );
  }

  void _onForeground() {
    ref.read(todayProvider.notifier).refresh();
    // A notification button may have written to the database while the app was closed.
    ref.read(revisionProvider.notifier).bump();
    if (ref.read(settingsProvider).onboardingDone &&
        !ref.read(lockedProvider)) {
      unawaited(ref.read(actionsProvider).markSeen(ref.read(todayProvider)));
      unawaited(ref.read(cloudBackupProvider).autoBackupIfDue());
    }
    unawaited(ref.read(reminderSyncProvider).resync());
  }

  Future<void> _offerUpdate() async {
    if (_offeringUpdate ||
        !mounted ||
        !_inForeground ||
        ref.read(lockedProvider) ||
        !ref.read(settingsProvider).onboardingDone)
      return;
    _offeringUpdate = true;
    try {
      final release = await _prompter.releaseToOffer(recordOffer: false);
      if (!mounted ||
          !_inForeground ||
          ref.read(lockedProvider) ||
          !ref.read(settingsProvider).onboardingDone)
        return;
      final ctx = _rootKey.currentContext;
      if (release != null && ctx != null && ctx.mounted) {
        await _prompter.markOffered(release.version);
        if (!ctx.mounted) return;
        await showUpdateSheet(
          ctx,
          release,
          onSkip: () => _prompter.skip(release.version),
        );
      }
    } catch (e) {
      debugPrint('Offering an update failed: $e');
    } finally {
      _offeringUpdate = false;
    }
  }

  /// The back button must not walk through the screens hidden behind the lock.
  @override
  Future<bool> didPopRoute() async {
    if (ref.read(lockedProvider)) {
      await SystemNavigator.pop();
      return true;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockedProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        _inForeground = false;
        _updateTimer?.cancel();
        lock.paused();
      case AppLifecycleState.resumed:
        _inForeground = true;
        lock.resumed();
        _waitForLockCheck();
        _onForeground();
      case AppLifecycleState.hidden || AppLifecycleState.detached:
        _inForeground = false;
        _updateTimer?.cancel();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reminderSyncProvider);
    ref.watch(externalChangesProvider);
    final choice = ref.watch(settingsProvider.select((s) => s.theme));
    final locked = ref.watch(lockedProvider);
    final lockOn = ref.watch(settingsProvider.select((s) => s.lockOn));
    return RootRoutesScope(
      routes: _rootRoutes,
      child: MaterialApp.router(
        title: 'Daily Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: switch (choice) {
          ThemeChoice.system => ThemeMode.system,
          ThemeChoice.light => ThemeMode.light,
          ThemeChoice.dark => ThemeMode.dark,
        },
        routerConfig: _router,
        scaffoldMessengerKey: _messengerKey,
        builder: (context, child) => PrivacyCover(
          enabled: lockOn,
          stayCovered: _lockCheck != null,
          child: Stack(
            children: [
              // While locked the app underneath is kept out of the accessibility tree and out of reach.
              ExcludeFocus(
                excluding: locked,
                child: ExcludeSemantics(
                  excluding: locked,
                  child: IgnorePointer(ignoring: locked, child: child),
                ),
              ),
              if (locked) const Positioned.fill(child: LockScreen()),
            ],
          ),
        ),
      ),
    );
  }
}
