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
  const CloudRestore(this.text, this.preview, this.file);
  final String text;
  final BackupPreview preview;
  final DriveFileInfo file;
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
  static const _dueKey = 'cloud.backupDue';
  static const _fileKey = 'cloud.file';
  static const _oldFileIdKey = 'cloud.fileId';
  static const _oldFileModifiedKey = 'cloud.fileModified';
  static const _sessionLostKey = 'cloud.sessionLost';
  static const _autoFailureKey = 'cloud.autoFailure';
  static const autoEvery = Duration(hours: 20);
  static const _clockMargin = Duration(minutes: 10);

  @visibleForTesting
  BackupService get backupForTest => _backup;

  bool get configured => _auth.configured;
  String? get email => _prefs.getString(_emailKey);
  bool get autoBackup => _prefs.getBool(_autoKey) ?? false;

  /// Whether Google wants the user to sign in again before Drive works. The
  /// account stays shown meanwhile: a session that did not come back at start
  /// may only mean there was no network.
  bool get sessionLost => _prefs.getBool(_sessionLostKey) ?? false;

  /// Why the last automatic backup did not run through, until a backup works.
  /// Waiting for Wi-Fi or a network is not a failure.
  String? get lastAutoBackupFailure => _prefs.getString(_autoFailureKey);

  DateTime? get lastBackupAt {
    final ms = _prefs.getInt(_lastKey);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> setAutoBackup(bool on) => _prefs.setBool(_autoKey, on);

  Future<void>? _restoringSession;

  /// Picks up a previous sign-in without asking; call once at start.
  Future<void> restoreSession() async {
    if (_restoringSession != null) return _restoringSession;
    final future = _doRestoreSession();
    _restoringSession = future;
    try {
      await future;
    } finally {
      _restoringSession = null;
    }
  }

  Future<void> _doRestoreSession() async {
    final e = await _auth.restoreSession();
    if (e != null) await _prefs.setString(_emailKey, e);
  }

  Future<String> signIn() async {
    final String e;
    try {
      e = await _auth.signIn();
    } on DriveException {
      // A declined Drive permission can leave an account that Google picks up
      // again at the next start, with no access to Drive.
      await _prefs.setBool(_sessionLostKey, true);
      rethrow;
    }
    // Another account's last backup says nothing about this one.
    if (e != email) await _prefs.remove(_lastKey);
    await _prefs.setString(_emailKey, e);
    await _prefs.remove(_sessionLostKey);
    await _prefs.remove(_autoFailureKey);
    return e;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _prefs.remove(_emailKey);
    await _prefs.remove(_autoKey);
    await _prefs.remove(_lastKey);
    await _prefs.remove(_dueKey);
    await _prefs.remove(_sessionLostKey);
    await _prefs.remove(_autoFailureKey);
  }

  /// Runs a Drive call, noting when Google wants the user to sign in again.
  Future<T> _onDrive<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DriveException catch (e) {
      if (e.needsSignIn) await _prefs.setBool(_sessionLostKey, true);
      rethrow;
    }
  }

  /// The Drive file this install wrote or restored last, and its modified
  /// time. Both go in one setting, `id@ms`: kept apart, a stop between the two
  /// writes paired a new file with an old time, and this install's own backup
  /// read as another phone's. Earlier versions kept two settings; they are read
  /// until the next write replaces them.
  ({String id, int modified})? _fileOnRecord() {
    final kept = _prefs.getString(_fileKey);
    if (kept == null) {
      final id = _prefs.getString(_oldFileIdKey);
      final modified = _prefs.getInt(_oldFileModifiedKey);
      return id == null || modified == null
          ? null
          : (id: id, modified: modified);
    }
    final at = kept.lastIndexOf('@');
    final modified = at < 0 ? null : int.tryParse(kept.substring(at + 1));
    return modified == null
        ? null
        : (id: kept.substring(0, at), modified: modified);
  }

  Future<void> _keepFileOnRecord(DriveFileInfo f) async {
    await _prefs.setString(
      _fileKey,
      '${f.id}@${f.modified.millisecondsSinceEpoch}',
    );
    await _prefs.remove(_oldFileIdKey);
    await _prefs.remove(_oldFileModifiedKey);
  }

  /// Whether this install wrote [f] and nothing changed it since. Versions
  /// that did not keep the file id kept the time of the last backup, and a
  /// file no newer than that is the one this install wrote then. That time is
  /// the phone's clock and the file's is Google's, so the file may be up to
  /// [_clockMargin] newer: a phone clock behind Google's would otherwise stop
  /// automatic backup for good. The cost is that another phone's backup made
  /// within that margin of this one's is written over.
  bool _wroteThis(DriveFileInfo f) {
    final kept = _fileOnRecord();
    if (kept == null) {
      final last = lastBackupAt;
      return last != null && !f.modified.isAfter(last.add(_clockMargin));
    }
    return kept.id == f.id &&
        kept.modified == f.modified.millisecondsSinceEpoch;
  }

  /// The backup on Drive when this install did not write it or it changed
  /// since, such as another phone's: only "Back up now" replaces it. Null when
  /// there is none, or it is this install's own.
  Future<DriveFileInfo?> otherBackupOnDrive() => _oneAtATime(() async {
    if (_restoringSession != null) await _restoringSession;
    final f = await _onDrive(_drive.info);
    return f == null || _wroteThis(f) ? null : f;
  });

  Future<void>? _driveJobs;

  /// Runs [job] after any Drive job already under way: two backups never both
  /// find no file on Drive and each create one, and a look at the file never
  /// answers for one that a running backup or restore is about to replace.
  Future<T> _oneAtATime<T>(Future<T> Function() job) {
    final run = (_driveJobs ?? Future<void>.value()).then((_) => job());
    late final Future<void> done;
    done = run.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_driveJobs, done)) _driveJobs = null;
    });
    _driveJobs = done;
    return run;
  }

  Future<BackupStatus?> _blocked({required bool overrideWifiOnly}) async {
    if (!await _network.isOnline()) return BackupStatus.offline;
    if (_wifiOnly() && !overrideWifiOnly && !await _network.isOnWifi())
      return BackupStatus.waitingForWifi;
    return null;
  }

  Future<BackupOutcome> backupNow({bool overrideWifiOnly = false}) =>
      _oneAtATime(() => _backupNow(overrideWifiOnly: overrideWifiOnly));

  Future<BackupOutcome> _backupNow({required bool overrideWifiOnly}) async {
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
      final f = await _drive.upload(await _backup.encodeForUpload());
      await _prefs.setInt(_lastKey, _now().millisecondsSinceEpoch);
      await _prefs.remove(_dueKey);
      await _keepFileOnRecord(f);
      await _prefs.remove(_sessionLostKey);
      await _prefs.remove(_autoFailureKey);
      return const BackupOutcome(BackupStatus.done);
    } on DriveException catch (e) {
      if (e.needsSignIn) await _prefs.setBool(_sessionLostKey, true);
      return BackupOutcome(
        e.needsSignIn ? BackupStatus.signInNeeded : BackupStatus.failed,
        e.message,
      );
    } catch (e) {
      debugPrint('Backup failed: $e');
      return const BackupOutcome(BackupStatus.failed, 'The backup failed.');
    }
  }

  /// Downloads the stored backup for a confirmation step, after any backup
  /// under way has landed. Null when there is none. Throws [DriveException] on
  /// a Drive problem and [FormatException] when the file is not valid.
  Future<CloudRestore?> fetchForRestore({bool overrideWifiOnly = false}) =>
      _oneAtATime(() => _fetchForRestore(overrideWifiOnly: overrideWifiOnly));

  Future<CloudRestore?> _fetchForRestore({
    required bool overrideWifiOnly,
  }) async {
    if (_restoringSession != null) await _restoringSession;
    final blocked = await _blocked(overrideWifiOnly: overrideWifiOnly);
    if (blocked == BackupStatus.offline)
      throw const DriveException('You are offline.');
    if (blocked == BackupStatus.waitingForWifi)
      throw const DriveException(
        'Connect to Wi-Fi, or allow mobile data for this restore.',
        needsWifi: true,
      );
    final info = await _onDrive(_drive.info);
    if (info == null) return null;
    final text = await _onDrive(() => _drive.download(file: info));
    if (text == null) return null;
    return CloudRestore(text, _backup.preview(text), info);
  }

  Future<void> restore(String text) => _backup.restore(text);

  /// Takes [file] as this install's own once its backup is restored here: the
  /// phone now holds what it holds, so automatic backup may write over it.
  /// A backup this install wrote over [file] since it was fetched, while the
  /// user was confirming, stays the one on record; it holds the data just
  /// replaced, so the next automatic backup is due at once.
  Future<void> restoredFrom(DriveFileInfo file) => _oneAtATime(() async {
    final kept = _fileOnRecord();
    if (kept != null &&
        kept.id == file.id &&
        kept.modified > file.modified.millisecondsSinceEpoch) {
      await _prefs.setBool(_dueKey, true);
      return;
    }
    await _keepFileOnRecord(file);
  });

  Future<void>? _autoRunning;

  /// Backs up if automatic backup is on, we are signed in, there is something
  /// to protect, the last backup is older than [autoEvery], and the backup on
  /// Drive is the one this install wrote, if there is one. Never throws.
  Future<void> autoBackupIfDue() async {
    if (_autoRunning != null) return _autoRunning;
    final future = _doAutoBackup();
    _autoRunning = future;
    try {
      await future;
    } finally {
      _autoRunning = null;
    }
  }

  Future<void> _doAutoBackup() async {
    String? failure;
    try {
      if (_restoringSession != null) await _restoringSession;
      await _oneAtATime(() async {
        if (!autoBackup || email == null) return;
        final last = lastBackupAt;
        final now = _now();
        if (_prefs.getBool(_dueKey) != true &&
            last != null &&
            !now.isBefore(last) &&
            now.difference(last) < autoEvery) {
          return;
        }
        if ((await _backup.repo.habits()).isEmpty) return;
        if (await _blocked(overrideWifiOnly: false) != null) return;
        final remote = await _onDrive(_drive.info);
        if (remote != null && !_wroteThis(remote)) return;
        final r = await _backupNow(overrideWifiOnly: false);
        if (r.status != BackupStatus.done) failure = r.message;
      });
    } catch (e) {
      debugPrint('Automatic backup skipped: $e');
      failure = e is DriveException ? e.message : 'The backup failed.';
    }
    if (failure == null) return;
    try {
      await _prefs.setString(_autoFailureKey, failure!);
    } catch (e) {
      debugPrint('Could not note the failed automatic backup: $e');
    }
  }
}
