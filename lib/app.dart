import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/update_provider.dart';
import 'presentation/features/update/update_dialog.dart';
import 'presentation/features/lock/app_lock_screen.dart';
import 'presentation/router/app_router.dart';

class DailyTrackerApp extends ConsumerStatefulWidget {
  const DailyTrackerApp({super.key});

  @override
  ConsumerState<DailyTrackerApp> createState() => _DailyTrackerAppState();
}

class _DailyTrackerAppState extends ConsumerState<DailyTrackerApp> {
  bool? _hasSeenOnboarding;
  bool _isLocked = false;
  bool _isLoading = true;
  bool _hasShownUpdateDialog = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool(AppConstants.prefFirstLaunch) ?? false;
    final appLockEnabled = prefs.getBool(AppConstants.prefAppLockEnabled) ?? false;

    setState(() {
      _hasSeenOnboarding = hasSeenOnboarding;
      _isLocked = appLockEnabled;
      _isLoading = false;
    });
  }

  void _onUnlock() {
    setState(() => _isLocked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _hasSeenOnboarding == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(null),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final themeState = ref.watch(themeProvider);
    final updateAsync = ref.watch(updateCheckProvider);

    if (_isLocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(null),
        darkTheme: AppTheme.darkTheme(null),
        themeMode: themeState.themeMode,
        home: AppLockScreen(onUnlock: _onUnlock),
      );
    }

    // Handle update check result — show dialog once per app session
    updateAsync.whenData((update) {
      if (update != null && mounted && !_hasShownUpdateDialog) {
        _hasShownUpdateDialog = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navContext = rootNavigatorKey.currentState?.context;
          if (navContext != null && navContext.mounted) {
            UpdateDialog.show(navContext, update);
          }
        });
      }
    });

    return MaterialApp.router(
      title: 'Daily Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(null),
      darkTheme: AppTheme.darkTheme(null),
      themeMode: themeState.themeMode,
      routerConfig: AppRouter.router(_hasSeenOnboarding!),
    );
  }
}
