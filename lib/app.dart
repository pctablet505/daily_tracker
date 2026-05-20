import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/router/app_router.dart';

class DailyTrackerApp extends ConsumerStatefulWidget {
  const DailyTrackerApp({super.key});

  @override
  ConsumerState<DailyTrackerApp> createState() => _DailyTrackerAppState();
}

class _DailyTrackerAppState extends ConsumerState<DailyTrackerApp> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(null),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final themeState = ref.watch(themeProvider);

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
