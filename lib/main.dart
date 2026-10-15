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
  final scheduler = LocalNotificationsScheduler();
  await scheduler.init();
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      photoStoreProvider.overrideWithValue(await openPhotoStore()),
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
  unawaited(startServices(container, prefs));
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DailyTrackerApp(),
    ),
  );
}

/// The photos in the app's own folder. The picker leaves its own copy of each
/// photo in the cache, and the store removes it once the photo is stored.
Future<DiskPhotoStore> openPhotoStore() async => DiskPhotoStore(
  Directory(p.join((await getApplicationSupportDirectory()).path, 'media')),
  cache: await getTemporaryDirectory(),
);

/// The tidying a start does while the first screen shows: shared copies of
/// a backup that are old, the photo a pick that outlived the app was for,
/// then the stored photos nothing refers to.
Future<void> startServices(
  ProviderContainer container,
  SharedPreferences prefs, {
  Future<String?> Function() lostPhoto = lostImagePickerPhoto,
}) async {
  final actions = container.read(actionsProvider);
  await Future.wait([
    SystemFileService().clearOldShares(),
    recoverLostPhoto(
      prefs,
      lostPhoto: lostPhoto,
      repo: container.read(repositoryProvider),
      actions: actions,
    ).whenComplete(actions.sweepOrphanPhotos),
  ]);
}
