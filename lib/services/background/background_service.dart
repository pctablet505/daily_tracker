import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../notification/notification_service.dart';
import '../sync/sync_service.dart';

const String bgUpdateCheckTask = 'dailyTrackerUpdateCheck';
const String bgSyncTask = 'dailyTrackerAutoSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    switch (task) {
      case bgUpdateCheckTask:
        await _checkForUpdates();
        break;
      case bgSyncTask:
        await _performBackgroundSync();
        break;
    }
    return Future.value(true);
  });
}

Future<void> _checkForUpdates() async {
  try {
    // Update check logic will be implemented in UpdateService
    // For now, just log that background check ran
    print('Background update check executed');
  } catch (e) {
    print('Background update check failed: $e');
  }
}

Future<void> _performBackgroundSync() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final autoSync = prefs.getBool(AppConstants.prefAutoSync) ?? true;
    final wifiOnly = prefs.getBool(AppConstants.prefWifiOnlySync) ?? true;

    if (!autoSync) return;

    // Actual sync requires Google Sign-In which needs user interaction
    // Background sync would queue pending operations
    print('Background sync executed');
  } catch (e) {
    print('Background sync failed: $e');
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
      existingWorkPolicy: ExistingWorkPolicy.keep,
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
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
