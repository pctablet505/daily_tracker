import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
const driveFileName = 'daily-tracker-backup.json';

/// An error with a message fit to show. [needsSignIn] means signing in again would fix it.
class DriveException implements Exception {
  const DriveException(this.message, {this.needsSignIn = false});
  final String message;
  final bool needsSignIn;
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

  Future<DriveFileInfo?> info() async {
    final res = await _send(
      'GET',
      Uri.https(_api, '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name='$driveFileName' and trashed=false",
        'fields': 'files(id,modifiedTime,size)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '10',
      }),
    );
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw const DriveException('Google Drive sent an unreadable reply.');
      }
      final files = (decoded['files'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .toList();
      if (files.isEmpty) return null;
      final f = files.firstWhere(
        (m) => (int.tryParse('${m['size']}') ?? 0) > 0,
        orElse: () => files.first,
      );
      return DriveFileInfo(
        id: f['id']! as String,
        modified: DateTime.parse(f['modifiedTime']! as String),
        size: int.tryParse('${f['size']}') ?? 0,
      );
    } on DriveException {
      rethrow;
    } catch (_) {
      throw const DriveException('Google Drive sent an unreadable reply.');
    }
  }

  /// Stores [json], replacing the previous backup.
  Future<DriveFileInfo> upload(String json) async {
    var id = (await info())?.id;
    var createdNew = false;
    if (id == null) {
      final created = await _send(
        'POST',
        Uri.https(_api, '/drive/v3/files'),
        body: jsonEncode({
          'name': driveFileName,
          'parents': ['appDataFolder'],
        }),
        contentType: 'application/json',
      );
      try {
        id =
            (jsonDecode(utf8.decode(created.bodyBytes))
                    as Map<String, Object?>)['id']!
                as String;
      } catch (_) {
        throw const DriveException('Google Drive sent an unreadable reply.');
      }
      createdNew = true;
    }
    try {
      await _send(
        'PATCH',
        Uri.https(_api, '/upload/drive/v3/files/$id', {'uploadType': 'media'}),
        body: json,
        contentType: 'application/json',
      );
    } catch (_) {
      if (createdNew) {
        try {
          await _send('DELETE', Uri.https(_api, '/drive/v3/files/$id'));
        } catch (_) {}
      }
      rethrow;
    }
    return (await info()) ??
        DriveFileInfo(
          id: id,
          modified: DateTime.now().toUtc(),
          size: utf8.encode(json).length,
        );
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
