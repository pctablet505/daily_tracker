import 'dart:async';

import 'package:flutter/material.dart';
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
import 'ui/shell.dart';
import 'ui/sheets/update_sheet.dart';
import 'ui/theme/theme.dart';
import 'ui/widgets/privacy_cover.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter buildRouter({
  required bool Function() onboardingDone,
  String initialLocation = '/',
}) {
  return GoRouter(
    navigatorKey: _rootKey,
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
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/habits/packs',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PacksScreen(
          openId: s.uri.queryParameters['open'],
          import: s.uri.queryParameters['import'] == '1',
        ),
      ),
      GoRoute(
        path: '/habit/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => HabitEditScreen(
          preset: s.extra is HabitForm ? s.extra! as HabitForm : null,
        ),
      ),
      GoRoute(
        path: '/habit/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => HabitDetailScreen(habitId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/habit/:id/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => HabitEditScreen(habitId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/backup',
        parentNavigatorKey: _rootKey,
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
  late final GoRouter _router = buildRouter(
    onboardingDone: () => ref.read(settingsProvider).onboardingDone,
  );
  StreamSubscription<String>? _taps;
  late final UpdatePrompter _prompter = UpdatePrompter(
    prefs: ref.read(sharedPrefsProvider),
    now: ref.read(clockProvider),
    check: () => ref.read(updateServiceProvider).check(),
    isOnWifi: () => ref.read(networkProvider).isOnWifi(),
    isOnline: () => ref.read(networkProvider).isOnline(),
    wifiOnly: () => ref.read(settingsProvider).wifiOnlyUpdate,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scheduler = ref.read(reminderSchedulerProvider);
    _taps = scheduler.taps.listen(_openPayload);
    unawaited(
      scheduler.launchPayload().then((p) {
        if (p != null) _openPayload(p);
      }),
    );
    unawaited(ref.read(cloudBackupProvider).restoreSession());
    // An update offer is held back while locked; offer it once the user is in.
    ref.listenManual(lockedProvider, (was, now) {
      if (was == true && !now) {
        Timer(const Duration(seconds: 2), () => unawaited(_offerUpdate()));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onForeground();
      Timer(const Duration(seconds: 4), () => unawaited(_offerUpdate()));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_taps?.cancel());
    super.dispose();
  }

  void _openPayload(String payload) {
    if (!ref.read(settingsProvider).onboardingDone) return;
    final habit = parseHabitPayload(payload);
    if (habit != null) {
      _router.go('/');
      unawaited(_router.push('/habit/${habit.habitId}'));
    } else {
      ref.read(selectedDayProvider.notifier).select(null);
      _router.go('/');
    }
  }

  void _onForeground() {
    ref.read(todayProvider.notifier).refresh();
    // A notification button may have written to the database while the app was closed.
    ref.read(revisionProvider.notifier).bump();
    unawaited(ref.read(actionsProvider).markSeen(ref.read(todayProvider)));
    unawaited(ref.read(reminderSyncProvider).resync());
    unawaited(ref.read(cloudBackupProvider).autoBackupIfDue());
  }

  Future<void> _offerUpdate() async {
    if (!mounted || ref.read(lockedProvider)) return;
    try {
      final release = await _prompter.releaseToOffer();
      final ctx = _rootKey.currentContext;
      if (release != null && ctx != null && ctx.mounted) {
        await showUpdateSheet(
          ctx,
          release,
          onSkip: () => _prompter.skip(release.version),
        );
      }
    } catch (e) {
      debugPrint('Offering an update failed: $e');
    }
  }

  /// The back button must not walk through the screens hidden behind the lock.
  @override
  Future<bool> didPopRoute() async => ref.read(lockedProvider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockedProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        lock.paused();
      case AppLifecycleState.resumed:
        lock.resumed();
        _onForeground();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
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
    return MaterialApp.router(
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
      builder: (context, child) => PrivacyCover(
        enabled: lockOn,
        child: Stack(
          children: [
            // While locked the app underneath is kept out of the accessibility tree and out of reach.
            ExcludeSemantics(
              excluding: locked,
              child: IgnorePointer(ignoring: locked, child: child),
            ),
            if (locked) const Positioned.fill(child: LockScreen()),
          ],
        ),
      ),
    );
  }
}
