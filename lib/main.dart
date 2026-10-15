import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'services/files.dart';
import 'services/lock.dart';
import 'services/notifications.dart';
import 'services/photo_picker.dart';
import 'services/photo_store.dart';
import 'state/lock_controller.dart';
import 'state/providers.dart';
import 'state/restored_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbDir = await getDatabasesPath();
  final db = await openAppDatabase(
    databaseFactory,
    p.join(dbDir, databaseFileName),
    removeLegacyIn: dbDir,
  );
  final prefs = await SharedPreferences.getInstance();
  await markSetUpIfHabitsExist(HabitRepository(db), prefs);
  unawaited(SystemFileService().clearOldShares());
  final support = await getApplicationSupportDirectory();
  final scheduler = LocalNotificationsScheduler();
  await scheduler.init();
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      photoStoreProvider.overrideWithValue(
        DiskPhotoStore(Directory(p.join(support.path, 'media'))),
      ),
      reminderSchedulerProvider.overrideWithValue(scheduler),
      lockServiceProvider.overrideWithValue(
        LockService(
          prefs: prefs,
          biometrics: LocalAuthBiometrics(),
          now: DateTime.now,
        ),
      ),
    ],
  );
  unawaited(
    recoverLostPhoto(
      prefs,
      lostPhoto: lostImagePickerPhoto,
      repo: container.read(repositoryProvider),
      actions: container.read(actionsProvider),
    ),
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DailyTrackerApp(),
    ),
  );
}
