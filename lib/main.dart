import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/services/dependency_injection.dart';
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

  runApp(
    const ProviderScope(
      child: DailyTrackerApp(),
    ),
  );
}
