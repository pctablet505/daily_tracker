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

  Future<drive.DriveApi?> _getDriveApi() async {
    final user = _googleSignIn.currentUser;
    if (user == null) return null;

    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) return null;

    return drive.DriveApi(authClient);
  }

  Future<bool> shouldSync() async {
    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool(AppConstants.prefWifiOnlySync) ?? true;

    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      return result == ConnectivityResult.wifi;
    }
    return true;
  }

  Future<bool> uploadBackup(DatabaseHelper db) async {
    if (!await shouldSync()) return false;

    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    try {
      // Get all tasks and serialize
      final tasks = await db.getAllActiveTasks();
      final completions = await db.getDailyCompletionsRange(
        DateTime.now().subtract(const Duration(days: 365)),
        DateTime.now(),
      );

      final backupData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': tasks.map((t) => t.toMap()).toList(),
        'completions': completions.map((c) => c.toMap()).toList(),
      };

      final jsonString = jsonEncode(backupData);
      final bytes = utf8.encode(jsonString);

      // Check if backup file already exists
      final existingFiles = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name='${AppConstants.syncFileName}'",
      );

      final media = drive.Media(Stream.fromIterable([bytes]), bytes.length);
      final file = drive.File()
        ..name = AppConstants.syncFileName
        ..parents = ['appDataFolder'];

      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        // Update existing file
        final fileId = existingFiles.files!.first.id!;
        await driveApi.files.update(file, fileId, uploadMedia: media);
      } else {
        // Create new file
        await driveApi.files.create(file, uploadMedia: media);
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

    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

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
