import 'package:flutter/widgets.dart';
import '../../core/utils/app_logger.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/dependency_injection.dart';
import '../../data/local/database_helper.dart';
import '../../data/repositories/task_repository.dart';
import '../notification/reminder_service.dart';
import '../sync/sync_service.dart';
import '../../presentation/features/update/update_dialog.dart';

const String bgUpdateCheckTask = 'dailyTrackerUpdateCheck';
const String bgSyncTask = 'dailyTrackerAutoSync';
const String bgDailyResetTask = 'dailyTrackerReset';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    setupDependencies();

    switch (task) {
      case bgUpdateCheckTask:
        await _checkForUpdates();
        break;
      case bgSyncTask:
        await _performBackgroundSync();
        break;
      case bgDailyResetTask:
        await _performDailyReset();
        break;
    }
    return Future.value(true);
  });
}

Future<void> _checkForUpdates() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool(AppConstants.prefWifiOnlyUpdates) ?? true;

    if (wifiOnly) {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.wifi) {
        AppLogger.d('Background update check skipped: not on Wi-Fi');
        return;
      }
    }

    final service = UpdateService();
    final update = await service.checkForUpdate();

    if (update != null) {
      // Store pending update so UI can show it on next launch
      await prefs.setString(AppConstants.prefPendingUpdateVersion, update.version);
      await prefs.setString(AppConstants.prefPendingUpdateUrl, update.downloadUrl);
      await prefs.setString(AppConstants.prefPendingUpdateChangelog, update.changelog);
    }
  } catch (e) {
    AppLogger.e('Background update check failed', e);
  }
}

Future<void> _performBackgroundSync() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final autoSync = prefs.getBool(AppConstants.prefAutoSync) ?? true;

    if (!autoSync) return;

    final syncService = getIt<SyncService>();
    final shouldSync = await syncService.shouldSync();
    if (!shouldSync) return;

    // Attempt sync if signed in
    final isSignedIn = await syncService.isSignedIn();
    if (isSignedIn) {
      final db = getIt<DatabaseHelper>();
      await syncService.uploadBackup(db);
    }
  } catch (e) {
    AppLogger.e('Background sync failed', e);
  }
}

Future<void> _performDailyReset() async {
  try {
    final db = getIt<DatabaseHelper>();
    final repository = TaskRepository(db);
    await repository.resetRecurringTasksForNewDay();

    // Also reschedule any recurring task reminders
    final recurringTasks = await repository.getRecurringTasks();
    final reminderService = ReminderService();
    for (final task in recurringTasks) {
      if (task.reminderTime != null) {
        await reminderService.scheduleTaskReminder(task);
      }
    }
  } catch (e) {
    AppLogger.e('Daily reset failed', e);
  }
}

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> registerUpdateCheck() async {
    await Workmanager().registerPeriodicTask(
      'update-check',
      bgUpdateCheckTask,
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.update,
    );
  }

  static Future<void> registerAutoSync() async {
    await Workmanager().registerPeriodicTask(
      'auto-sync',
      bgSyncTask,
      frequency: const Duration(hours: 6),
      constraints: Constraints(
        networkType: NetworkType.unmetered,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.update,
    );
  }

  static Future<void> registerDailyReset() async {
    await Workmanager().registerPeriodicTask(
      'daily-reset',
      bgDailyResetTask,
      frequency: const Duration(hours: 24),
      initialDelay: _calculateInitialDelayToMidnight(),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.update,
    );
  }

  static Duration _calculateInitialDelayToMidnight() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 0, 5);
    return tomorrow.difference(now);
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
