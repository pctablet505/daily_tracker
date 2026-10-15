import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const githubOwner = 'pctablet505';
const githubRepo = 'daily_tracker';
const sourceUrl = 'https://github.com/$githubOwner/$githubRepo';

List<int>? _parts(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  s = s.split('+').first.split('-').first;
  if (s.isEmpty) return null;
  final out = <int>[];
  for (final part in s.split('.')) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out;
}

/// True when [remote] is a higher version than [current]. Accepts a leading
/// "v" and ignores a "+build" or "-suffix". Anything unreadable is not newer.
bool isNewerVersion(String remote, String current) {
  final r = _parts(remote);
  final c = _parts(current);
  if (r == null || c == null) return false;
  final n = r.length > c.length ? r.length : c.length;
  for (var i = 0; i < n; i++) {
    final a = i < r.length ? r[i] : 0;
    final b = i < c.length ? c[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

final class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    this.apkSize,
    this.sha256Url,
  });
  final String version;
  final String notes;
  final String apkUrl;
  final int? apkSize;

  /// A `.sha256` file published next to the apk, when there is one.
  final String? sha256Url;
}

bool _isHttpsUrl(Object? u) {
  if (u is! String) return false;
  final uri = Uri.tryParse(u);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

/// Reads a GitHub release. Null when it is a draft or prerelease, has no apk, or its tag is not a version.
ReleaseInfo? parseRelease(Map<String, Object?> json) {
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = json['tag_name'];
  if (tag is! String ||
      !RegExp(
        r'^[vV]?\d+(?:\.\d+)*(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
      ).hasMatch(tag) ||
      tag.contains('..') ||
      _parts(tag) == null) {
    return null;
  }
  final assets = (json['assets'] as List<Object?>? ?? const [])
      .whereType<Map<String, Object?>>()
      .toList();
  Map<String, Object?>? find(bool Function(String) test) => assets
      .where(
        (a) =>
            a['name'] is String && test((a['name']! as String).toLowerCase()),
      )
      .firstOrNull;
  final apk = find((n) => n.endsWith('.apk'));
  if (apk == null || !_isHttpsUrl(apk['browser_download_url'])) return null;
  final sha = find((n) => n.endsWith('.apk.sha256') || n.endsWith('.sha256'));
  final rawShaUrl = sha?['browser_download_url'];
  final body = (json['body'] as String?)?.replaceAll(r'\n', '\n').trim() ?? '';
  return ReleaseInfo(
    version: tag.replaceFirst(RegExp('^[vV]'), ''),
    notes: body.isEmpty ? 'No release notes.' : body,
    apkUrl: apk['browser_download_url']! as String,
    apkSize: (apk['size'] as num?)?.toInt(),
    sha256Url: _isHttpsUrl(rawShaUrl) ? rawShaUrl as String : null,
  );
}

sealed class UpdateCheck {
  const UpdateCheck();
}

final class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.release);
  final ReleaseInfo release;
}

final class UpToDate extends UpdateCheck {
  const UpToDate();
}

final class UpdateCheckFailed extends UpdateCheck {
  const UpdateCheckFailed(this.message);
  final String message;
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

class CancelToken {
  final _c = Completer<void>();
  bool get isCancelled => _c.isCompleted;
  Future<void> get whenCancelled => _c.future;
  void cancel() {
    if (!_c.isCompleted) _c.complete();
  }
}

class UpdateService {
  UpdateService({
    http.Client? client,
    Future<String> Function()? currentVersion,
    Future<Directory> Function()? cacheDir,
  }) : _client = client ?? http.Client(),
       _currentVersion =
           currentVersion ??
           (() async => (await PackageInfo.fromPlatform()).version),
       _cacheDir = cacheDir ?? getTemporaryDirectory;

  final http.Client _client;
  final Future<String> Function() _currentVersion;
  final Future<Directory> Function() _cacheDir;

  static const _timeout = Duration(seconds: 20);

  Future<UpdateCheck> check() async {
    try {
      final res = await _client
          .get(
            Uri.https(
              'api.github.com',
              '/repos/$githubOwner/$githubRepo/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(_timeout);
      if (res.statusCode == 404) return const UpToDate();
      if (res.statusCode != 200)
        return UpdateCheckFailed('GitHub answered ${res.statusCode}.');
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map<String, Object?>)
        return const UpdateCheckFailed('GitHub sent something unexpected.');
      final release = parseRelease(json);
      if (release == null ||
          !isNewerVersion(release.version, await _currentVersion()))
        return const UpToDate();
      return UpdateAvailable(release);
    } on TimeoutException {
      return const UpdateCheckFailed('Could not reach GitHub in time.');
    } on FormatException {
      return const UpdateCheckFailed('GitHub sent something unexpected.');
    } catch (e) {
      debugPrint('Update check failed: $e');
      return const UpdateCheckFailed(
        'Could not check for updates. Are you online?',
      );
    }
  }

  Future<String?> _publishedSha(String url) async {
    if (!_isHttpsUrl(url)) {
      throw const UpdateException('Could not read the published checksum.');
    }
    final res = await _client.get(Uri.parse(url)).timeout(_timeout);
    if (res.statusCode != 200)
      throw const UpdateException('Could not read the published checksum.');
    final m = RegExp(r'\b([0-9a-fA-F]{64})\b')
        .firstMatch(utf8.decode(res.bodyBytes));
    if (m == null)
      throw const UpdateException('The published checksum is not readable.');
    return m[1]!.toLowerCase();
  }

  /// Downloads the apk and checks it against the published checksum (or, when
  /// the release has none, its size). A file that fails is deleted. Android
  /// itself still refuses an update signed with a different key.
  Future<File> download(
    ReleaseInfo r, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancel,
  }) async {
    if (!_isHttpsUrl(r.apkUrl)) {
      throw const UpdateException('The download URL is not secure.');
    }
    final dir = await _cacheDir();
    final target = File(p.join(dir.path, 'daily-tracker-${r.version}.apk'));
    final part = File('${target.path}.part');
    try {
      final expected = r.sha256Url == null
          ? null
          : await _publishedSha(r.sha256Url!);
      if (cancel?.isCancelled ?? false) throw const UpdateCancelled();
      final req = http.Request('GET', Uri.parse(r.apkUrl));
      final res = await _client.send(req).timeout(_timeout);
      if (cancel?.isCancelled ?? false) throw const UpdateCancelled();
      if (res.statusCode != 200)
        throw UpdateException('The download failed (${res.statusCode}).');
      final total = res.contentLength ?? r.apkSize ?? -1;
      final sink = part.openWrite();
      final digest = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      final done = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = res.stream.timeout(_timeout).listen(
        (chunk) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        },
        onDone: () => done.complete(),
        onError: done.completeError,
        cancelOnError: true,
      );
      unawaited(
        cancel?.whenCancelled.then((_) {
          if (!done.isCompleted) done.completeError(const UpdateCancelled());
          return sub.cancel();
        }),
      );
      try {
        await done.future;
      } finally {
        await sink.close();
        hasher.close();
      }
      if (expected != null) {
        if (digest.events.single.toString() != expected) {
          throw const UpdateException(
            'The downloaded file is damaged (its checksum does not match). Try again.',
          );
        }
      } else if (r.apkSize != null && received != r.apkSize) {
        throw const UpdateException(
          'The downloaded file is the wrong size. Try again.',
        );
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      try {
        for (final f in dir.listSync().whereType<File>()) {
          final base = p.basename(f.path);
          if (f.path != target.path &&
              base.startsWith('daily-tracker-') &&
              (base.endsWith('.apk') || base.endsWith('.apk.part'))) {
            await f.delete();
          }
        }
      } catch (_) {}
      return target;
    } on UpdateCancelled {
      rethrow;
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException(
        'The download timed out. Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('Update download failed: $e');
      throw const UpdateException(
        'The download failed. Check your connection and try again.',
      );
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  /// Hands the apk to Android's installer. Returns a message when it could not start.
  Future<String?> install(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done
        ? null
        : (result.message.isEmpty
              ? 'Could not open the installer.'
              : result.message);
  }
}

/// Collects the single event of a chunked conversion.
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}
