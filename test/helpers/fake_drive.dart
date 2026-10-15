import 'dart:convert';

import 'package:daily_tracker/services/drive_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final class FakeAuth implements DriveAuth {
  FakeAuth({this.signedIn = true, this.configured = true});
  bool signedIn;
  @override
  final bool configured;
  String? email = 'me@example.com';

  /// Thrown by [signIn], as when the user declines Google's Drive permission.
  DriveException? signInError;

  @override
  Future<String?> restoreSession() async => signedIn ? email : null;
  @override
  Future<String> signIn() async {
    if (signInError case final e?) throw e;
    signedIn = true;
    return email!;
  }

  @override
  Future<void> signOut() async => signedIn = false;
  @override
  Future<Map<String, String>> headers() async {
    if (!signedIn)
      throw const DriveException('Sign in to Google first.', needsSignIn: true);
    return {'Authorization': 'Bearer token-123'};
  }
}

/// A tiny Google Drive: one app-data folder holding files by id.
final class FakeDrive {
  final files = <String, ({String name, String content, DateTime modified})>{};
  final requests = <String>[];
  final trashed = <String>{};
  var _n = 0;
  int failWith = 0;
  DateTime now = DateTime.utc(2026, 10, 11, 12);

  /// How long creating a file takes, so that two uploads can overlap.
  Duration createDelay = Duration.zero;

  Future<http.Response> handle(http.Request r) async {
    requests.add(
      '${r.method} ${r.url.path}${r.url.query.isEmpty ? '' : '?${r.url.query}'}',
    );
    expect(r.headers['Authorization'], 'Bearer token-123');
    if (failWith != 0)
      return http.Response('{"error":{"message":"boom"}}', failWith);
    final path = r.url.path;
    if (r.method == 'GET' && path == '/drive/v3/files') {
      expect(r.url.queryParameters['spaces'], 'appDataFolder');
      final q = r.url.queryParameters['q']!;
      final newestFirst =
          r.url.queryParameters['orderBy'] == 'modifiedTime desc';
      final hits =
          files.entries
              .where(
                (e) =>
                    q.contains("name='${e.value.name}'") &&
                    !(q.contains('trashed=false') && trashed.contains(e.key)),
              )
              .toList()
            ..sort(
              (a, b) => newestFirst
                  ? b.value.modified.compareTo(a.value.modified)
                  : a.value.modified.compareTo(b.value.modified),
            );
      return http.Response(
        jsonEncode({
          'files': [
            for (final e in hits)
              {
                'id': e.key,
                'name': e.value.name,
                'modifiedTime': e.value.modified.toIso8601String(),
                'size': '${utf8.encode(e.value.content).length}',
              },
          ],
        }),
        200,
      );
    }
    if (r.method == 'POST' && path == '/drive/v3/files') {
      await Future<void>.delayed(createDelay);
      final m = jsonDecode(r.body) as Map<String, Object?>;
      expect(m['parents'], ['appDataFolder']);
      final id = 'file${_n++}';
      files[id] = (name: m['name']! as String, content: '', modified: now);
      return http.Response(jsonEncode({'id': id}), 200);
    }
    final upload = RegExp(r'^/upload/drive/v3/files/(.+)$').firstMatch(path);
    if (r.method == 'PATCH' && upload != null) {
      expect(r.url.queryParameters['uploadType'], 'media');
      final id = upload[1]!;
      if (!files.containsKey(id)) return http.Response('{}', 404);
      files[id] = (
        name: files[id]!.name,
        content: utf8.decode(r.bodyBytes),
        modified: now,
      );
      return http.Response(jsonEncode({'id': id}), 200);
    }
    final get = RegExp(r'^/drive/v3/files/(.+)$').firstMatch(path);
    if (r.method == 'GET' &&
        get != null &&
        r.url.queryParameters['alt'] == 'media') {
      final f = files[get[1]];
      return f == null
          ? http.Response('{}', 404)
          : http.Response.bytes(utf8.encode(f.content), 200);
    }
    return http.Response('unexpected ${r.method} $path', 500);
  }
}
