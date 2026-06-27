import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/services/dependency_injection.dart';
import 'core/utils/app_logger.dart';
import 'data/local/database_helper.dart';
import 'data/repositories/task_repository.dart';
import 'services/background/background_service.dart';
import 'services/notification/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  setupDependencies();

  // Service initialization should never prevent the app from launching.
  await _safeInitialize(
      () => NotificationService().initialize(), 'NotificationService');
  await _safeInitialize(
      () => BackgroundService.initialize(), 'BackgroundService');
  await _safeInitialize(
      () => BackgroundService.registerUpdateCheck(), 'registerUpdateCheck');
  await _safeInitialize(
      () => BackgroundService.registerAutoSync(), 'registerAutoSync');
  await _safeInitialize(
      () => BackgroundService.registerDailyReset(), 'registerDailyReset');

  // Reset recurring tasks on app startup
  await _resetRecurringTasks();

  runApp(
    const ProviderScope(
      child: DailyTrackerApp(),
    ),
  );
}

Future<void> _safeInitialize(Future<void> Function() init, String name,
    {Duration timeout = const Duration(seconds: 3)}) async {
  try {
    await init().timeout(timeout);
  } catch (e) {
    AppLogger.e('Failed to initialize $name', e);
  }
}

Future<void> _resetRecurringTasks() async {
  try {
    final db = getIt<DatabaseHelper>();
    final repository = TaskRepository(db);
    await repository.resetRecurringTasksForNewDay();
  } catch (e) {
    AppLogger.e('Failed to reset recurring tasks', e);
  }
}
