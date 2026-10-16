import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
const driveFileName = 'daily-tracker-backup.json';

/// An error with a message fit to show. [needsSignIn] means signing in again would fix it,
/// and [needsWifi] that Wi-Fi would, or allowing mobile data this once.
class DriveException implements Exception {
  const DriveException(
    this.message, {
    this.needsSignIn = false,
    this.needsWifi = false,
  });
  final String message;
  final bool needsSignIn;
  final bool needsWifi;
  @override
  String toString() => message;
}

abstract interface class DriveAuth {
  /// Whether this build has the Google client id it needs to sign in.
  bool get configured;

  /// Signs in again without asking, if the user did before. Returns the email, or null.
  Future<String?> restoreSession();

  /// Asks the user to pick an account and allow access to the app's Drive folder.
  Future<String> signIn();

  Future<void> signOut();

  /// Authorization headers for a Drive request. Throws a [DriveException] with `needsSignIn` when signed out.
  Future<Map<String, String>> headers();
}

/// What to tell the user when Google's sign-in fails. The library reports a window the user
/// closed and an app setup Google does not accept (a wrong client id or signing key) the same
/// way, as "canceled", so that case must not blame the user alone.
String signInFailureMessage(GoogleSignInExceptionCode code) =>
    code == GoogleSignInExceptionCode.canceled
    ? 'Sign-in did not finish. If you closed the Google window, try again. '
          'If you chose an account and it still fails, Google does not accept '
          'this build of the app.'
    : 'Could not sign in to Google (${code.name}).';

/// Sign-in through Google Play services. Needs a web client id from the app's
/// Google Cloud project, passed to the build as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.
final class GoogleDriveAuth implements DriveAuth {
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  bool _initialized = false;
  GoogleSignInAccount? _account;

  @override
  bool get configured => _serverClientId.isNotEmpty;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    _initialized = true;
  }

  @override
  Future<String?> restoreSession() async {
    if (!configured) return null;
    try {
      await _init();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      return _account?.email;
    } catch (e) {
      debugPrint('Restoring the Google session failed: $e');
      return null;
    }
  }

  @override
  Future<String> signIn() async {
    if (!configured)
      throw const DriveException('Google sign-in is not set up in this build.');
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [driveScope],
      );
      await account.authorizationClient.authorizeScopes(const [driveScope]);
      _account = account;
      return account.email;
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in failed: ${e.code.name}: ${e.description}');
      throw DriveException(signInFailureMessage(e.code));
    }
  }

  @override
  Future<void> signOut() async {
    if (!configured) return;
    await _init();
    await GoogleSignIn.instance.signOut();
    _account = null;
  }

  @override
  Future<Map<String, String>> headers() async {
    var account = _account;
    if (account == null) {
      await restoreSession();
      account = _account;
    }
    if (account == null)
      throw const DriveException('Sign in to Google first.', needsSignIn: true);
    try {
      final h = await account.authorizationClient.authorizationHeaders(const [
        driveScope,
      ], promptIfNecessary: false);
      if (h == null)
        throw const DriveException(
          'Google needs you to allow access again.',
          needsSignIn: true,
        );
      return h;
    } on GoogleSignInException {
      throw const DriveException(
        'Google needs you to sign in again.',
        needsSignIn: true,
      );
    }
  }
}

final class DriveFileInfo {
  const DriveFileInfo({
    required this.id,
    required this.modified,
    required this.size,
  });
  final String id;
  final DateTime modified;
  final int size;
}

/// One backup file in the app's private Drive folder (`appDataFolder`), which
/// the user cannot see or clutter and no other app can read.
class DriveBackup {
  DriveBackup(this._auth, this._http);

  final DriveAuth _auth;
  final http.Client _http;

  static const _api = 'www.googleapis.com';
  static const _timeout = Duration(seconds: 60);

  Future<http.Response> _send(
    String method,
    Uri url, {
    Object? body,
    String? contentType,
  }) async {
    try {
      final req = http.Request(method, url)
        ..headers.addAll(await _auth.headers());
      if (contentType != null) req.headers['Content-Type'] = contentType;
      if (body is String) req.bodyBytes = utf8.encode(body);
      final res = await http.Response.fromStream(
        await _http.send(req).timeout(_timeout),
      ).timeout(_timeout);
      if (res.statusCode == 401)
        throw const DriveException(
          'Google needs you to sign in again.',
          needsSignIn: true,
        );
      if (res.statusCode == 403)
        throw const DriveException(
          'Google Drive refused. Your Drive may be full, or access was removed.',
        );
      if (res.statusCode < 200 || res.statusCode >= 300)
        throw DriveException('Google Drive answered ${res.statusCode}.');
      return res;
    } on DriveException {
      rethrow;
    } on TimeoutException {
      throw const DriveException(
        'Google Drive did not answer in time. Check your connection.',
      );
    } on SocketException {
      throw const DriveException('Lost the connection to Google Drive.');
    } on http.ClientException {
      throw const DriveException('Lost the connection to Google Drive.');
    }
  }

  /// What Drive is asked to send back about a file it lists or writes.
  static const _fileFields = 'id,modifiedTime,size';

  static Map<String, Object?> _decode(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {}
    throw const DriveException('Google Drive sent an unreadable reply.');
  }

  static DriveFileInfo _fileInfo(Map<String, Object?> f) {
    try {
      return DriveFileInfo(
        id: f['id']! as String,
        modified: DateTime.parse(f['modifiedTime']! as String),
        size: int.tryParse('${f['size']}') ?? 0,
      );
    } catch (_) {
      throw const DriveException('Google Drive sent an unreadable reply.');
    }
  }

  /// The newest backup file, preferring one with something in it.
  Future<DriveFileInfo?> _newest() async {
    final res = await _send(
      'GET',
      Uri.https(_api, '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name='$driveFileName' and trashed=false",
        'fields': 'files($_fileFields)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '10',
      }),
    );
    final listed = _decode(res)['files'] ?? const [];
    if (listed is! List) {
      throw const DriveException('Google Drive sent an unreadable reply.');
    }
    final files = listed.whereType<Map<String, Object?>>().toList();
    if (files.isEmpty) return null;
    return _fileInfo(
      files.firstWhere(
        (m) => (int.tryParse('${m['size']}') ?? 0) > 0,
        orElse: () => files.first,
      ),
    );
  }

  /// The backup on Drive, or null when there is none. An empty file is none:
  /// it is what a first backup that broke off between creating the file and
  /// writing it leaves behind.
  Future<DriveFileInfo?> info() async {
    final f = await _newest();
    return f == null || f.size == 0 ? null : f;
  }

  /// Stores [json], replacing the previous backup, and returns the file as
  /// Drive's reply to the write describes it. Asking again afterwards could
  /// fail, or miss the file while Drive's list catches up after a create.
  Future<DriveFileInfo> upload(String json) async {
    var id = (await _newest())?.id;
    var createdNew = false;
    if (id == null) {
      id = _fileInfo(
        _decode(
          await _send(
            'POST',
            Uri.https(_api, '/drive/v3/files', {'fields': _fileFields}),
            body: jsonEncode({
              'name': driveFileName,
              'parents': ['appDataFolder'],
            }),
            contentType: 'application/json',
          ),
        ),
      ).id;
      createdNew = true;
    }
    try {
      return _fileInfo(
        _decode(
          await _send(
            'PATCH',
            Uri.https(_api, '/upload/drive/v3/files/$id', {
              'uploadType': 'media',
              'fields': _fileFields,
            }),
            body: json,
            contentType: 'application/json',
          ),
        ),
      );
    } catch (_) {
      if (createdNew) {
        try {
          await _send('DELETE', Uri.https(_api, '/drive/v3/files/$id'));
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// The backup text, or null when there is none yet.
  Future<String?> download({DriveFileInfo? file}) async {
    final f = file ?? await info();
    if (f == null) return null;
    final res = await _send(
      'GET',
      Uri.https(_api, '/drive/v3/files/${f.id}', {'alt': 'media'}),
    );
    try {
      return utf8.decode(res.bodyBytes);
    } on FormatException {
      throw const FormatException('The backup file is damaged.');
    }
  }
}
