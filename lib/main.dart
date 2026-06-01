import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/services/dependency_injection.dart';
import 'data/local/database_helper.dart';
import 'data/repositories/task_repository.dart';
import 'services/background/background_service.dart';
import 'services/notification/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  setupDependencies();
  await NotificationService().initialize();
  await BackgroundService.initialize();
  await BackgroundService.registerUpdateCheck();
  await BackgroundService.registerAutoSync();
  await BackgroundService.registerDailyReset();

  // Reset recurring tasks on app startup
  await _resetRecurringTasks();

  runApp(
    const ProviderScope(
      child: DailyTrackerApp(),
    ),
  );
}

Future<void> _resetRecurringTasks() async {
  try {
    final db = getIt<DatabaseHelper>();
    final repository = TaskRepository(db);
    await repository.resetRecurringTasksForNewDay();
  } catch (e) {
    debugPrint('Failed to reset recurring tasks: $e');
  }
}
