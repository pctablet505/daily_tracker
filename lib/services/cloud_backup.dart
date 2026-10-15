import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';
import 'drive_backup.dart';

abstract interface class NetworkInfo {
  Future<bool> isOnline();
  Future<bool> isOnWifi();
}

final class ConnectivityNetwork implements NetworkInfo {
  Future<List<ConnectivityResult>> _check() =>
      Connectivity().checkConnectivity();

  @override
  Future<bool> isOnline() async =>
      (await _check()).any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnWifi() async {
    final r = await _check();
    return r.contains(ConnectivityResult.wifi) ||
        r.contains(ConnectivityResult.ethernet);
  }
}

enum BackupStatus { done, waitingForWifi, offline, signInNeeded, failed }

final class BackupOutcome {
  const BackupOutcome(this.status, [this.message = '']);
  final BackupStatus status;
  final String message;
}

final class CloudRestore {
  const CloudRestore(this.text, this.preview, this.modified);
  final String text;
  final BackupPreview preview;
  final DateTime? modified;
}

/// Backup to the app's private Google Drive folder: sign-in state, the Wi-Fi
/// rule, the daily automatic backup, and restore. Photos are never uploaded.
class CloudBackup {
  CloudBackup({
    required this._auth,
    required this._drive,
    required this._backup,
    required this._network,
    required this._prefs,
    required this._now,
    required this._wifiOnly,
  });

  final DriveAuth _auth;
  final DriveBackup _drive;
  final BackupService _backup;
  final NetworkInfo _network;
  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final bool Function() _wifiOnly;

  static const _emailKey = 'cloud.email';
  static const _autoKey = 'cloud.auto';
  static const _lastKey = 'cloud.last';
  static const autoEvery = Duration(hours: 20);

  @visibleForTesting
  BackupService get backupForTest => _backup;

  bool get configured => _auth.configured;
  String? get email => _prefs.getString(_emailKey);
  bool get autoBackup => _prefs.getBool(_autoKey) ?? false;

  DateTime? get lastBackupAt {
    final ms = _prefs.getInt(_lastKey);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> setAutoBackup(bool on) => _prefs.setBool(_autoKey, on);

  Future<void>? _restoringSession;

  /// Picks up a previous sign-in without asking; call once at start.
  Future<void> restoreSession() => _restoringSession ??= _doRestoreSession();

  Future<void> _doRestoreSession() async {
    try {
      final e = await _auth.restoreSession();
      if (e != null) await _prefs.setString(_emailKey, e);
    } finally {
      _restoringSession = null;
    }
  }

  Future<String> signIn() async {
    final e = await _auth.signIn();
    await _prefs.setString(_emailKey, e);
    return e;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _prefs.remove(_emailKey);
    await _prefs.remove(_autoKey);
  }

  Future<BackupStatus?> _blocked({required bool overrideWifiOnly}) async {
    if (!await _network.isOnline()) return BackupStatus.offline;
    if (_wifiOnly() && !overrideWifiOnly && !await _network.isOnWifi())
      return BackupStatus.waitingForWifi;
    return null;
  }

  Future<BackupOutcome> backupNow({
    bool automatic = false,
    bool overrideWifiOnly = false,
  }) async {
    if (_restoringSession != null) await _restoringSession;
    final blocked = await _blocked(overrideWifiOnly: overrideWifiOnly);
    if (blocked != null) {
      return BackupOutcome(
        blocked,
        blocked == BackupStatus.waitingForWifi
            ? 'Waiting for Wi-Fi.'
            : 'You are offline.',
      );
    }
    try {
      await _drive.upload(await _backup.encodeForUpload());
      await _prefs.setInt(_lastKey, _now().millisecondsSinceEpoch);
      return const BackupOutcome(BackupStatus.done);
    } on DriveException catch (e) {
      return BackupOutcome(
        e.needsSignIn ? BackupStatus.signInNeeded : BackupStatus.failed,
        e.message,
      );
    } catch (e) {
      debugPrint('Backup failed: $e');
      return const BackupOutcome(BackupStatus.failed, 'The backup failed.');
    }
  }

  /// Downloads the stored backup for a confirmation step. Null when there is none.
  /// Throws [DriveException] on a Drive problem and [FormatException] when the file is not valid.
  Future<CloudRestore?> fetchForRestore({bool overrideWifiOnly = false}) async {
    if (_restoringSession != null) await _restoringSession;
    final blocked = await _blocked(overrideWifiOnly: overrideWifiOnly);
    if (blocked == BackupStatus.offline)
      throw const DriveException('You are offline.');
    if (blocked == BackupStatus.waitingForWifi)
      throw const DriveException(
        'Connect to Wi-Fi, or allow mobile data for this restore.',
      );
    final info = await _drive.info();
    if (info == null) return null;
    final text = await _drive.download(file: info);
    if (text == null) return null;
    return CloudRestore(text, _backup.preview(text), info.modified);
  }

  Future<void> restore(String text) => _backup.restore(text);

  Future<void>? _autoRunning;

  /// Backs up if automatic backup is on, we are signed in, there is something
  /// to protect, and the last backup is older than [autoEvery]. Never throws.
  Future<void> autoBackupIfDue() => _autoRunning ??= _doAutoBackup();

  Future<void> _doAutoBackup() async {
    try {
      if (_restoringSession != null) await _restoringSession;
      if (!autoBackup || email == null) return;
      final last = lastBackupAt;
      final now = _now();
      if (last != null &&
          !now.isBefore(last) &&
          now.difference(last) < autoEvery) {
        return;
      }
      if ((await _backup.repo.habits()).isEmpty) return;
      await backupNow(automatic: true);
    } catch (e) {
      debugPrint('Automatic backup skipped: $e');
    } finally {
      _autoRunning = null;
    }
  }
}
