import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/backup_service.dart';
import '../services/cloud_backup.dart';
import '../services/drive_backup.dart';
import '../services/updater.dart';
import 'providers.dart';

/// "2.0.0" from the installed app. Tests replace it.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    repo: ref.watch(repositoryProvider),
    readSettings: () => ref.read(settingsProvider),
    applySettings: (m) =>
        ref.read(settingsProvider.notifier).update((s) => s.withImported(m)),
    safetyDir: () async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'safety'),
    ),
    now: ref.watch(clockProvider),
    appVersion: () => ref.read(appVersionProvider.future),
  );
});

final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

final driveAuthProvider = Provider<DriveAuth>((ref) => GoogleDriveAuth());
final networkProvider = Provider<NetworkInfo>((ref) => ConnectivityNetwork());

final cloudBackupProvider = Provider<CloudBackup>((ref) {
  return CloudBackup(
    auth: ref.watch(driveAuthProvider),
    drive: DriveBackup(
      ref.watch(driveAuthProvider),
      ref.watch(httpClientProvider),
    ),
    backup: ref.watch(backupServiceProvider),
    network: ref.watch(networkProvider),
    prefs: ref.watch(sharedPrefsProvider),
    now: ref.watch(clockProvider),
    wifiOnly: () => ref.read(settingsProvider).wifiOnlyBackup,
  );
});

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(client: ref.watch(httpClientProvider)),
);
