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

({List<int> numbers, List<String> pre})? _parts(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  s = s.split('+').first;
  final dash = s.indexOf('-');
  final pre = dash < 0 ? const <String>[] : s.substring(dash + 1).split('.');
  if (dash >= 0) s = s.substring(0, dash);
  if (s.isEmpty) return null;
  final out = <int>[];
  for (final part in s.split('.')) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return (numbers: out, pre: pre);
}

/// Orders prerelease labels as semver does: field by field, numbers below
/// words, and a longer label above its own prefix.
int _comparePre(List<String> a, List<String> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    final x = int.tryParse(a[i]);
    final y = int.tryParse(b[i]);
    final c = x != null && y != null
        ? x.compareTo(y)
        : x != null
        ? -1
        : y != null
        ? 1
        : a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

/// True when [remote] is a higher version than [current]. Accepts a leading
/// "v" and ignores a "+build". A "-suffix" marks a prerelease, which is older
/// than the same version without one. Anything unreadable is not newer.
bool isNewerVersion(String remote, String current) {
  final r = _parts(remote);
  final c = _parts(current);
  if (r == null || c == null) return false;
  final n = r.numbers.length > c.numbers.length
      ? r.numbers.length
      : c.numbers.length;
  for (var i = 0; i < n; i++) {
    final a = i < r.numbers.length ? r.numbers[i] : 0;
    final b = i < c.numbers.length ? c.numbers[i] : 0;
    if (a != b) return a > b;
  }
  if (r.pre.isEmpty || c.pre.isEmpty) return r.pre.isEmpty && c.pre.isNotEmpty;
  return _comparePre(r.pre, c.pre) > 0;
}

final class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    this.apkName,
    this.apkSize,
    this.sha256Url,
  });
  final String version;
  final String notes;
  final String apkUrl;

  /// The apk's file name on the release; the checksum file names it.
  final String? apkName;
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
      !RegExp(r'^[vV]?\d+(?:\.\d+)*(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
          .hasMatch(tag) ||
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
  final apkName = apk['name']! as String;
  final sha =
      find((n) => n == '${apkName.toLowerCase()}.sha256') ??
      find((n) => n.endsWith('.sha256'));
  final rawShaUrl = sha?['browser_download_url'];
  final body = (json['body'] as String?)?.replaceAll(r'\n', '\n').trim() ?? '';
  return ReleaseInfo(
    version: tag.replaceFirst(RegExp('^[vV]'), ''),
    notes: body.isEmpty ? 'No release notes.' : body,
    apkUrl: apk['browser_download_url']! as String,
    apkName: apkName,
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

/// Waits for [work], but throws [UpdateCancelled] as soon as [cancel] fires
/// instead of waiting for a server that may take its time to answer.
Future<T> _unlessCancelled<T>(Future<T> work, CancelToken? cancel) async {
  if (cancel == null) return work;
  final value = await Future.any([
    work,
    cancel.whenCancelled.then<T>((_) => throw const UpdateCancelled()),
  ]);
  if (cancel.isCancelled) throw const UpdateCancelled();
  return value;
}

/// The hash a `sha256sum` file gives for [fileName]. A file holding one bare
/// hash, or one line when the name is unknown, applies to the apk too.
String? _checksumFor(String text, String? fileName) {
  final hashes = <String?, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final m = RegExp(r'^\s*([0-9a-fA-F]{64})(?:\s+\*?(\S.*?))?\s*$')
        .firstMatch(line);
    if (m == null) continue;
    final name = m[2] == null ? null : p.basename(m[2]!);
    hashes.putIfAbsent(name, () => m[1]!.toLowerCase());
  }
  if (fileName != null && hashes.containsKey(fileName)) return hashes[fileName];
  if (hashes.length != 1) return null;
  return fileName == null || hashes.keys.single == null
      ? hashes.values.single
      : null;
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

  Future<String> _publishedSha(ReleaseInfo r, CancelToken? cancel) async {
    final url = r.sha256Url!;
    if (!_isHttpsUrl(url)) {
      throw const UpdateException('Could not read the published checksum.');
    }
    final res = await _unlessCancelled(
      _client.get(Uri.parse(url)).timeout(_timeout),
      cancel,
    );
    if (res.statusCode != 200)
      throw const UpdateException('Could not read the published checksum.');
    final sha = _checksumFor(utf8.decode(res.bodyBytes), r.apkName);
    if (sha == null)
      throw const UpdateException('The published checksum is not readable.');
    return sha;
  }

  static int _nextPart = 0;

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
    // Its own name, so a cancelled download that ends late cannot delete the
    // file of the one that replaced it.
    final part = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}-${_nextPart++}.part',
    );
    try {
      final expected = r.sha256Url == null
          ? null
          : await _publishedSha(r, cancel);
      final req = http.AbortableRequest(
        'GET',
        Uri.parse(r.apkUrl),
        abortTrigger: cancel?.whenCancelled,
      );
      final res = await _unlessCancelled(
        _client.send(req).timeout(_timeout),
        cancel,
      );
      if (res.statusCode != 200)
        throw UpdateException('The download failed (${res.statusCode}).');
      final total = res.contentLength ?? r.apkSize ?? -1;
      final sink = part.openWrite();
      final digest = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      final sub = res.stream.timeout(_timeout).listen((chunk) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      });
      try {
        await _unlessCancelled(sub.asFuture<void>(), cancel);
      } finally {
        await sub.cancel();
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
      // Renaming over the old file replaces it in one step; deleting it first
      // leaves a moment in which another download's caller finds nothing.
      await part.rename(target.path);
      try {
        final stale = DateTime.now().subtract(const Duration(hours: 1));
        for (final f in dir.listSync().whereType<File>()) {
          final base = p.basename(f.path);
          if (!base.startsWith('daily-tracker-') || f.path == target.path) {
            continue;
          }
          // Another download may still be writing its part file; only one
          // nothing has written to for an hour is left over.
          if (base.endsWith('.apk') ||
              (base.endsWith('.part') &&
                  f.lastModifiedSync().isBefore(stale))) {
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
