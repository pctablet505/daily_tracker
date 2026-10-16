import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:daily_tracker/services/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const apkBytes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
final apkSha = sha256.convert(apkBytes).toString();

Map<String, Object?> release({
  String tag = 'v2.1.0',
  bool prerelease = false,
  bool draft = false,
  String body = '- Fixed a bug\n- Faster',
  bool apk = true,
  bool sha = true,
}) => {
  'tag_name': tag,
  'prerelease': prerelease,
  'draft': draft,
  'body': body,
  'assets': [
    if (apk)
      {
        'name': 'daily-tracker-2.1.0.apk',
        'browser_download_url': 'https://example.test/app.apk',
        'size': apkBytes.length,
      },
    if (sha)
      {
        'name': 'daily-tracker-2.1.0.apk.sha256',
        'browser_download_url': 'https://example.test/app.apk.sha256',
        'size': 90,
      },
    {
      'name': 'source.zip',
      'browser_download_url': 'https://example.test/src.zip',
      'size': 1,
    },
  ],
};

void main() {
  group('comparing versions', () {
    for (final c in <(String, String, bool)>[
      ('2.1.0', '2.0.0', true),
      ('2.0.1', '2.0.0', true),
      ('3.0.0', '2.9.9', true),
      ('2.0.0', '2.0.0', false),
      ('1.9.9', '2.0.0', false),
      ('v2.1.0', '2.0.0', true),
      ('2.1.0', '2.0.0+3', true),
      ('2.0.0+9', '2.0.0+3', false),
      ('2.10.0', '2.9.0', true),
      ('2.1', '2.0.9', true),
      ('2.0.0.1', '2.0.0', true),
      ('2.0.0', '2.0.0-beta.1', true),
      ('2.0.0-beta.1', '2.0.0', false),
      ('2.0.0-beta.2', '2.0.0-beta.1', true),
      ('2.0.0-beta.10', '2.0.0-beta.9', true),
      ('2.0.0-rc.1', '2.0.0-beta.2', true),
      ('2.0.0-beta.1', '2.0.0-beta', true),
      ('2.0.0-beta.1', '2.0.0-beta.1', false),
      ('2.1.0-beta.1', '2.0.0', true),
      ('garbage', '2.0.0', false),
      ('2.0.0', 'garbage', false),
      ('', '2.0.0', false),
    ]) {
      test(
        '${c.$1} vs ${c.$2} -> newer: ${c.$3}',
        () => expect(isNewerVersion(c.$1, c.$2), c.$3),
      );
    }
  });

  group('reading a release', () {
    test('picks the apk, its size and its published checksum', () {
      final r = parseRelease(release())!;
      expect(r.version, '2.1.0');
      expect(r.apkUrl, 'https://example.test/app.apk');
      expect(r.apkSize, apkBytes.length);
      expect(r.sha256Url, 'https://example.test/app.apk.sha256');
      expect(r.notes, '- Fixed a bug\n- Faster');
    });

    test(
      'a release without a checksum file still parses, with none to check',
      () {
        expect(parseRelease(release(sha: false))!.sha256Url, isNull);
      },
    );

    test('is ignored when it is a draft, a prerelease, or has no apk', () {
      expect(parseRelease(release(draft: true)), isNull);
      expect(parseRelease(release(prerelease: true)), isNull);
      expect(parseRelease(release(apk: false)), isNull);
    });

    test('is ignored when the tag is not a version or has path traversal', () {
      expect(parseRelease(release(tag: 'nightly')), isNull);
      expect(parseRelease(release(tag: 'v2.1.0/../../evil')), isNull);
      expect(parseRelease(release(tag: 'v2.1.0\\evil')), isNull);
      expect(parseRelease(release(tag: 'v2..1.0')), isNull);
    });

    test(
      'takes the checksum file named for the apk when there are several',
      () {
        final json = release()
          ..['assets'] = [
            {
              'name': 'other.apk.sha256',
              'browser_download_url': 'https://example.test/other.apk.sha256',
            },
            ...(release()['assets']! as List<Object?>),
          ];
        final r = parseRelease(json)!;
        expect(r.sha256Url, 'https://example.test/app.apk.sha256');
        expect(r.apkName, 'daily-tracker-2.1.0.apk');
      },
    );

    test('literal backslash-n sequences in the notes become line breaks', () {
      expect(parseRelease(release(body: 'a\\nb'))!.notes, 'a\nb');
    });

    test('empty notes get a plain line', () {
      expect(parseRelease(release(body: ''))!.notes, isNotEmpty);
    });
  });

  group('checking for an update', () {
    UpdateService service(http.Client c) => UpdateService(
      client: c,
      currentVersion: () async => '2.0.0',
      cacheDir: () async => Directory.systemTemp,
    );

    test('finds a newer release', () async {
      final s = service(
        MockClient((r) async {
          expect(r.url.path, endsWith('/releases/latest'));
          return http.Response(jsonEncode(release()), 200);
        }),
      );
      final r = await s.check();
      expect(r, isA<UpdateAvailable>());
      expect((r as UpdateAvailable).release.version, '2.1.0');
    });

    test('says up to date when the release is not newer', () async {
      final s = service(
        MockClient(
          (_) async => http.Response(jsonEncode(release(tag: 'v2.0.0')), 200),
        ),
      );
      expect(await s.check(), isA<UpToDate>());
    });

    test('says up to date when there is nothing installable', () async {
      final s = service(
        MockClient(
          (_) async => http.Response(jsonEncode(release(apk: false)), 200),
        ),
      );
      expect(await s.check(), isA<UpToDate>());
    });

    test(
      'reports a failure, not "up to date", when the request fails',
      () async {
        expect(
          await service(MockClient((_) async => http.Response('nope', 500)))
              .check(),
          isA<UpdateCheckFailed>(),
        );
        expect(
          await service(MockClient((_) async => http.Response('not json', 200)))
              .check(),
          isA<UpdateCheckFailed>(),
        );
        expect(
          await service(
            MockClient((_) async => throw const SocketException('offline')),
          ).check(),
          isA<UpdateCheckFailed>(),
        );
      },
    );

    test('a repo with no releases yet is up to date', () async {
      expect(
        await service(
          MockClient(
            (_) async => http.Response('{"message":"Not Found"}', 404),
          ),
        ).check(),
        isA<UpToDate>(),
      );
    });
  });

  group('downloading', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('dt_upd_');
      addTearDown(() => dir.delete(recursive: true));
    });

    UpdateService service(http.Client c) => UpdateService(
      client: c,
      currentVersion: () async => '2.0.0',
      cacheDir: () async => dir,
    );

    ReleaseInfo info({
      String? sha = 'https://example.test/app.apk.sha256',
      int? size,
      String? name,
    }) => ReleaseInfo(
      version: '2.1.0',
      notes: 'n',
      apkUrl: 'https://example.test/app.apk',
      apkName: name,
      apkSize: size ?? apkBytes.length,
      sha256Url: sha,
    );

    MockClient server({
      String? shaText,
      int apkStatus = 200,
      List<int> body = apkBytes,
    }) => MockClient.streaming((req, _) async {
      if (req.url.path.endsWith('.sha256')) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(shaText ?? '$apkSha  daily-tracker-2.1.0.apk\n'),
          ),
          200,
        );
      }
      return http.StreamedResponse(
        Stream.value(body),
        apkStatus,
        contentLength: body.length,
      );
    });

    test(
      'saves the file when its checksum matches the published one',
      () async {
        final progress = <(int, int)>[];
        final f = await service(server())
            .download(info(), onProgress: (r, t) => progress.add((r, t)));
        expect(await f.readAsBytes(), apkBytes);
        expect(progress.last, (apkBytes.length, apkBytes.length));
      },
    );

    test('rejects and deletes a file whose checksum differs', () async {
      final s = service(server(shaText: '${'0' * 64}  x.apk'));
      await expectLater(
        s.download(info(), onProgress: (_, _) {}),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
      expect(dir.listSync().where((f) => f.path.endsWith('.apk')), isEmpty);
    });

    test(
      'rejects a wrong-sized file when there is no checksum to compare',
      () async {
        final s = service(server(body: [1, 2, 3]));
        await expectLater(
          s.download(info(sha: null), onProgress: (_, _) {}),
          throwsA(isA<UpdateException>()),
        );
        expect(dir.listSync().where((f) => f.path.endsWith('.apk')), isEmpty);
      },
    );

    test('accepts the right size when there is no checksum file', () async {
      final f = await service(server())
          .download(info(sha: null), onProgress: (_, _) {});
      expect(await f.readAsBytes(), apkBytes);
    });

    test('reports a failed download instead of hanging', () async {
      final s = service(server(apkStatus: 404));
      await expectLater(
        s.download(info(), onProgress: (_, _) {}),
        throwsA(isA<UpdateException>()),
      );
    });

    test('uses the checksum line that names the apk, not the first', () async {
      const name = 'daily-tracker-2.1.0.apk';
      final f = await service(
        server(
          shaText: '${'0' * 64}  daily-tracker-2.1.0-x86.apk\n$apkSha  $name\n',
        ),
      ).download(info(name: name), onProgress: (_, _) {});
      expect(await f.readAsBytes(), apkBytes);

      await expectLater(
        service(server(shaText: '$apkSha  other.apk\n${'0' * 64} *$name\n'))
            .download(info(name: name), onProgress: (_, _) {}),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
    });

    test('a checksum file that names only other files is refused', () async {
      await expectLater(
        service(server(shaText: '$apkSha  other.apk\n')).download(
          info(name: 'daily-tracker-2.1.0.apk'),
          onProgress: (_, _) {},
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(dir.listSync().where((f) => f.path.endsWith('.apk')), isEmpty);
    });

    test('reports a checksum file that cannot be read', () async {
      final s = service(server(shaText: 'not a hash'));
      await expectLater(
        s.download(info(), onProgress: (_, _) {}),
        throwsA(isA<UpdateException>()),
      );
    });

    test('a download can be cancelled and leaves nothing behind', () async {
      final started = Completer<void>();
      final s = service(
        MockClient.streaming((req, _) async {
          if (req.url.path.endsWith('.sha256'))
            return http.StreamedResponse(
              Stream.value(utf8.encode(apkSha)),
              200,
            );
          started.complete();
          return http.StreamedResponse(
            Stream.fromFuture(
              Future.delayed(const Duration(seconds: 5), () => apkBytes),
            ),
            200,
            contentLength: apkBytes.length,
          );
        }),
      );
      final token = CancelToken();
      final future = s.download(info(), onProgress: (_, _) {}, cancel: token);
      await started.future;
      token.cancel();
      await expectLater(future, throwsA(isA<UpdateCancelled>()));
      expect(
        dir.listSync().where(
          (f) => f.path.endsWith('.apk') || f.path.endsWith('.part'),
        ),
        isEmpty,
      );
    });

    test('Cancel ends the wait for a server that has not answered', () async {
      final asked = Completer<void>();
      var aborted = false;
      final s = service(
        MockClient.streaming((req, _) {
          if (req case http.Abortable(:final abortTrigger?)) {
            abortTrigger.then((_) => aborted = true);
          }
          asked.complete();
          return Completer<http.StreamedResponse>().future;
        }),
      );
      final token = CancelToken();
      final future = s.download(
        info(sha: null),
        onProgress: (_, _) {},
        cancel: token,
      );
      await asked.future;
      token.cancel();
      await expectLater(
        future.timeout(const Duration(seconds: 2)),
        throwsA(isA<UpdateCancelled>()),
      );
      expect(aborted, isTrue, reason: 'the request itself is aborted');
    });

    test('Cancel ends the wait for the checksum file', () async {
      final asked = Completer<void>();
      final s = service(
        MockClient((_) {
          asked.complete();
          return Completer<http.Response>().future;
        }),
      );
      final token = CancelToken();
      final future = s.download(info(), onProgress: (_, _) {}, cancel: token);
      await asked.future;
      token.cancel();
      await expectLater(
        future.timeout(const Duration(seconds: 2)),
        throwsA(isA<UpdateCancelled>()),
      );
    });

    test('a cancelled download whose server answers late leaves the next one alone', () async {
      final firstAnswer = Completer<void>();
      final second = StreamController<List<int>>();
      var calls = 0;
      final s = service(
        MockClient.streaming((req, _) async {
          if (++calls == 1) {
            await firstAnswer.future;
            return http.StreamedResponse(Stream.value(apkBytes), 200);
          }
          return http.StreamedResponse(second.stream, 200);
        }),
      );
      final token = CancelToken();
      final first = expectLater(
        s.download(info(sha: null), onProgress: (_, _) {}, cancel: token),
        throwsA(isA<UpdateCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      token.cancel();

      final gotChunk = Completer<void>();
      final next = s.download(
        info(sha: null),
        onProgress: (_, _) {
          if (!gotChunk.isCompleted) gotChunk.complete();
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      second.add(apkBytes.sublist(0, 5));
      await gotChunk.future;

      firstAnswer.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      second.add(apkBytes.sublist(5));
      await second.close();
      expect(await (await next).readAsBytes(), apkBytes);
    });

    test('two downloads of one version at once both end whole', () async {
      final bodies = [
        StreamController<List<int>>(),
        StreamController<List<int>>(),
      ];
      var calls = 0;
      final s = service(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(bodies[calls++].stream, 200),
        ),
      );
      final a = s.download(info(sha: null), onProgress: (_, _) {});
      final b = s.download(info(sha: null), onProgress: (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final body in bodies) {
        body.add(apkBytes.sublist(0, 5));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      for (final body in bodies) {
        body.add(apkBytes.sublist(5));
        await body.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await (await a).readAsBytes(), apkBytes);
      expect(await (await b).readAsBytes(), apkBytes);
    });

    test('a second download of one version replaces the file with no moment it is gone', () async {
      final bodies = [
        StreamController<List<int>>(),
        StreamController<List<int>>(),
      ];
      var calls = 0;
      final s = service(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(bodies[calls++].stream, 200),
        ),
      );
      final a = s.download(info(sha: null), onProgress: (_, _) {});
      final b = s.download(info(sha: null), onProgress: (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final target = File('${dir.path}/daily-tracker-2.1.0.apk');
      var seen = false;
      var gone = false;
      final probe = Timer.periodic(Duration.zero, (_) {
        if (target.existsSync()) {
          seen = true;
        } else if (seen) {
          gone = true;
        }
      });
      bodies[0].add(apkBytes);
      await bodies[0].close();
      await a;
      bodies[1].add(apkBytes);
      await bodies[1].close();
      await b;
      probe.cancel();
      expect(seen, isTrue);
      expect(gone, isFalse);
    });

    test("a finished download clears old files but not another download's part file", () async {
      File put(String name) => File('${dir.path}/$name')..writeAsBytesSync([0]);
      final old = put('daily-tracker-2.0.9.apk');
      final busy = put('daily-tracker-2.2.0.apk.part');
      final stale = put(
        'daily-tracker-2.0.9.apk.part',
      )..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
      final f = await service(server()).download(info(), onProgress: (_, _) {});
      expect(f.existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      expect(stale.existsSync(), isFalse);
      expect(busy.existsSync(), isTrue);
    });
  });
}
