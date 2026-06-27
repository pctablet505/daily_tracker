import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/utils/app_logger.dart';
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
      AppLogger.e('Google Sign-In error', e);
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
      AppLogger.e('Google Sign-In silent error', e);
      return null;
    }
  }

  Future<drive.DriveApi> _getDriveApi() async {
    var user = _googleSignIn.currentUser;
    if (user == null) {
      AppLogger.d(
          '_getDriveApi: currentUser is null, attempting signInSilently');
      user = await _googleSignIn.signInSilently();
    }
    AppLogger.d(
        '_getDriveApi: currentUser is ${user == null ? "NULL" : "NOT NULL"}');
    if (user == null) {
      throw Exception('Not signed in to Google. Please sign in again.');
    }

    AppLogger.d('_getDriveApi: requesting authenticated client');
    final authClient = await _googleSignIn.authenticatedClient();
    AppLogger.d('_getDriveApi: authClient obtained: ${authClient != null}');
    if (authClient == null) {
      throw Exception(
          'Google Drive authentication failed. Please sign in again.');
    }

    return drive.DriveApi(authClient);
  }

  Future<bool> shouldSync() async {
    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool(AppConstants.prefWifiOnlySync) ?? true;
    AppLogger.d('shouldSync: wifiOnly preference = $wifiOnly');

    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      AppLogger.d('shouldSync: connectivity result = $result');
      return result == ConnectivityResult.wifi;
    }
    return true;
  }

  Future<bool> uploadBackup(DatabaseHelper db) async {
    AppLogger.d('uploadBackup: checking shouldSync');
    final syncCheck = await shouldSync();
    AppLogger.d('uploadBackup: shouldSync result = $syncCheck');
    if (!syncCheck) return false;

    AppLogger.d('uploadBackup: getting DriveApi');
    late final drive.DriveApi driveApi;
    try {
      driveApi = await _getDriveApi();
    } catch (e) {
      AppLogger.e('uploadBackup: DriveApi auth failed', e);
      return false;
    }
    AppLogger.d('uploadBackup: driveApi obtained successfully');

    try {
      AppLogger.d('uploadBackup: gathering database tasks');
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

      AppLogger.d(
          'uploadBackup: checking existing backup files on Google Drive');
      // Check if backup file already exists
      final existingFiles = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name='${AppConstants.syncFileName}'",
      );
      AppLogger.d(
          'uploadBackup: found ${existingFiles.files?.length ?? 0} existing backup files');

      final media = drive.Media(Stream.fromIterable([bytes]), bytes.length);

      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        // Update existing file — do NOT set parents in update requests
        final fileId = existingFiles.files!.first.id!;
        final file = drive.File()..name = AppConstants.syncFileName;
        AppLogger.d('uploadBackup: updating existing file on Google Drive');
        await driveApi.files.update(file, fileId, uploadMedia: media);
        AppLogger.d('uploadBackup: update successful');
      } else {
        // Create new file
        final file = drive.File()
          ..name = AppConstants.syncFileName
          ..parents = ['appDataFolder'];
        AppLogger.d('uploadBackup: creating new backup file on Google Drive');
        await driveApi.files.create(file, uploadMedia: media);
        AppLogger.d('uploadBackup: creation successful');
      }

      // Update last sync time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          AppConstants.prefLastSyncTime, DateTime.now().toIso8601String());

      return true;
    } catch (e) {
      AppLogger.e('Upload backup failed', e);
      return false;
    }
  }

  Future<Map<String, dynamic>?> downloadBackup() async {
    if (!await shouldSync()) return null;

    late final drive.DriveApi driveApi;
    try {
      driveApi = await _getDriveApi();
    } catch (e) {
      AppLogger.e('downloadBackup: DriveApi auth failed', e);
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
      final media = await driveApi.files.get(fileId,
          downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final bytes = await media.stream.expand((x) => x).toList();
      final jsonString = utf8.decode(bytes);

      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.e('Download backup failed', e);
      return null;
    }
  }
}
