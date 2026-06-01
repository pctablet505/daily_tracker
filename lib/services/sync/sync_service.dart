import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../data/local/database_helper.dart';

class SyncService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive.appdata',
    ],
  );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      return account;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (e) {
      debugPrint('Google Sign-In silent error: $e');
      return null;
    }
  }

  Future<drive.DriveApi> _getDriveApi() async {
    var user = _googleSignIn.currentUser;
    if (user == null) {
      debugPrint('_getDriveApi: currentUser is null, attempting signInSilently...');
      user = await _googleSignIn.signInSilently();
    }
    debugPrint('_getDriveApi: currentUser is ${user == null ? "NULL" : "NOT NULL (email: ${user.email})"}');
    if (user == null) {
      throw Exception('Not signed in to Google. Please sign in again.');
    }

    debugPrint('_getDriveApi: calling authenticatedClient()...');
    final authClient = await _googleSignIn.authenticatedClient();
    debugPrint('_getDriveApi: authClient is ${authClient == null ? "NULL" : "NOT NULL"}');
    if (authClient == null) {
      throw Exception('Google Drive authentication failed. Please sign in again.');
    }

    return drive.DriveApi(authClient);
  }

  Future<bool> shouldSync() async {
    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool(AppConstants.prefWifiOnlySync) ?? true;
    debugPrint('shouldSync: wifiOnly preference = $wifiOnly');

    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      debugPrint('shouldSync: ConnectivityResult from plugin = $result');
      return result == ConnectivityResult.wifi;
    }
    return true;
  }

  Future<bool> uploadBackup(DatabaseHelper db) async {
    debugPrint('uploadBackup: checking shouldSync...');
    final syncCheck = await shouldSync();
    debugPrint('uploadBackup: shouldSync result = $syncCheck');
    if (!syncCheck) return false;

    debugPrint('uploadBackup: getting DriveApi...');
    late final drive.DriveApi driveApi;
    try {
      driveApi = await _getDriveApi();
    } catch (e) {
      debugPrint('uploadBackup: DriveApi auth failed: $e');
      return false;
    }
    debugPrint('uploadBackup: driveApi obtained successfully');

    try {
      debugPrint('uploadBackup: gathering database tasks...');
      final tasks = await db.getAllActiveTasks();
      final completions = await db.getDailyCompletionsRange(
        DateTime.now().subtract(const Duration(days: 365)),
        DateTime.now(),
      );
      final taskLogs = await db.getAllTaskLogs();

      final backupData = {
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': tasks.map((t) => t.toMap()).toList(),
        'completions': completions.map((c) => c.toMap()).toList(),
        'taskLogs': taskLogs.map((l) => l.toMap()).toList(),
      };

      final jsonString = jsonEncode(backupData);
      final bytes = utf8.encode(jsonString);

      debugPrint('uploadBackup: checking existing backup files on Google Drive...');
      // Check if backup file already exists
      final existingFiles = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name='${AppConstants.syncFileName}'",
      );
      debugPrint('uploadBackup: found ${existingFiles.files?.length ?? 0} existing backup files');

      final media = drive.Media(Stream.fromIterable([bytes]), bytes.length);

      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        // Update existing file — do NOT set parents in update requests
        final fileId = existingFiles.files!.first.id!;
        final file = drive.File()..name = AppConstants.syncFileName;
        debugPrint('uploadBackup: updating existing file $fileId on Google Drive...');
        await driveApi.files.update(file, fileId, uploadMedia: media);
        debugPrint('uploadBackup: update successful');
      } else {
        // Create new file
        final file = drive.File()
          ..name = AppConstants.syncFileName
          ..parents = ['appDataFolder'];
        debugPrint('uploadBackup: creating new backup file on Google Drive...');
        await driveApi.files.create(file, uploadMedia: media);
        debugPrint('uploadBackup: creation successful');
      }

      // Update last sync time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefLastSyncTime, DateTime.now().toIso8601String());

      return true;
    } catch (e) {
      debugPrint('Upload backup failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> downloadBackup() async {
    if (!await shouldSync()) return null;

    late final drive.DriveApi driveApi;
    try {
      driveApi = await _getDriveApi();
    } catch (e) {
      debugPrint('downloadBackup: DriveApi auth failed: $e');
      return null;
    }

    try {
      final existingFiles = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name='${AppConstants.syncFileName}'",
      );

      if (existingFiles.files == null || existingFiles.files!.isEmpty) {
        return null;
      }

      final fileId = existingFiles.files!.first.id!;
      final media = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final bytes = await media.stream.expand((x) => x).toList();
      final jsonString = utf8.decode(bytes);

      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Download backup failed: $e');
      return null;
    }
  }
}
