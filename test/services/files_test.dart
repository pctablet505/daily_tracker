import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daily_tracker/services/files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// A backup file holds the user's habits and notes. The copy handed to the share sheet and
/// the copy the file picker makes must not pile up in the app's cache.
final class _Picked implements PickedFile {
  _Picked(this.events, String text, {this.reportedLength})
    : _bytes = Uint8List.fromList(utf8.encode(text));

  final List<String> events;
  final int? reportedLength;
  final Uint8List _bytes;

  @override
  Future<int?> length() async => reportedLength ?? _bytes.length;

  @override
  Stream<List<int>> readAsByteStream() {
    events.add('read');
    return Stream.value(_bytes);
  }
}

void main() {
  late Directory tmp;
  late List<ShareParams> shared;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dt_files_');
    shared = [];
    addTearDown(() => tmp.delete(recursive: true));
  });

  SystemFileService service({
    Future<PickedFile?> Function()? pick,
    Future<void> Function()? clearPicked,
  }) => SystemFileService(
    tempDir: () async => tmp,
    share: (params) async => shared.add(params),
    pick: pick,
    clearPicked: clearPicked,
  );

  Directory sharedDir() =>
      Directory(p.join(tmp.path, SystemFileService.sharedFolder));

  File aged(
    String name,
    Duration age, {
    String folder = SystemFileService.sharedFolder,
  }) => File(p.join(tmp.path, folder, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(name)
    ..setLastModifiedSync(DateTime.now().subtract(age));

  group('sharing', () {
    test(
      'writes the file into its own folder and leaves it for the receiving app',
      () async {
        await service().shareText('backup.json', '{"a":1}');
        final f = File(p.join(sharedDir().path, 'backup.json'));
        expect(f.readAsStringSync(), '{"a":1}');
        expect(shared.single.files!.single.path, f.path);
        expect(
          f.existsSync(),
          isTrue,
          reason: 'the receiving app may still be reading it',
        );
      },
    );

    test(
      'the next share removes copies older than an hour and keeps newer ones',
      () async {
        final old = aged('old.json', const Duration(hours: 2));
        final recent = aged('recent.json', const Duration(minutes: 5));
        await service().shareText('new.json', 'z');
        expect(old.existsSync(), isFalse);
        expect(recent.existsSync(), isTrue);
        expect(File(p.join(sharedDir().path, 'new.json')).existsSync(), isTrue);
      },
    );

    test(
      'clearOldShares removes old copies, for when the app starts',
      () async {
        final old = aged('old.json', const Duration(hours: 3));
        final recent = aged('recent.json', const Duration(minutes: 1));
        await service().clearOldShares();
        expect(old.existsSync(), isFalse);
        expect(recent.existsSync(), isTrue);
      },
    );

    test(
      "old copies in the share plugin's own folder go too, fresh ones stay",
      () async {
        const plugin = SystemFileService.pluginShareFolder;
        final old = aged('old.json', const Duration(hours: 2), folder: plugin);
        final recent = aged(
          'recent.json',
          const Duration(minutes: 5),
          folder: plugin,
        );
        await service().clearOldShares();
        expect(old.existsSync(), isFalse);
        expect(recent.existsSync(), isTrue);
      },
    );

    test("a share also clears the plugin's old copy", () async {
      final old = aged(
        'old.json',
        const Duration(hours: 2),
        folder: SystemFileService.pluginShareFolder,
      );
      await service().shareText('new.json', 'z');
      expect(old.existsSync(), isFalse);
    });

    test('clearOldShares is fine when nothing was ever shared', () async {
      expect(sharedDir().existsSync(), isFalse);
      await service().clearOldShares();
    });

    test(
      'a file name that tries to leave the folder stays inside it',
      () async {
        await service().shareText('../../escape.json', 'x');
        expect(File(p.join(tmp.path, 'escape.json')).existsSync(), isFalse);
        expect(
          File(p.join(sharedDir().path, 'escape.json')).existsSync(),
          isTrue,
        );
      },
    );
  });

  group('picking', () {
    test("clears the picker's cache copy after the file is read", () async {
      final events = <String>[];
      final text = await service(
        pick: () async => _Picked(events, '{"ok":true}'),
        clearPicked: () async => events.add('clear'),
      ).pickAndReadText();
      expect(text, '{"ok":true}');
      expect(events, ['read', 'clear']);
    });

    test('also clears it when the file is too large to read', () async {
      final events = <String>[];
      await expectLater(
        service(
          pick: () async => _Picked(events, 'x', reportedLength: 99),
          clearPicked: () async => events.add('clear'),
        ).pickAndReadText(maxBytes: 10),
        throwsA(isA<FormatException>()),
      );
      expect(events, ['clear']);
    });

    test('also clears it when the file is not text', () async {
      final events = <String>[];
      final bad = _PickedBytes(events, Uint8List.fromList([0xff, 0xfe, 0x00]));
      await expectLater(
        service(
          pick: () async => bad,
          clearPicked: () async => events.add('clear'),
        ).pickAndReadText(),
        throwsA(isA<FormatException>()),
      );
      expect(events, ['read', 'clear']);
    });

    test('a failing cleanup does not lose the text that was read', () async {
      final text = await service(
        pick: () async => _Picked(<String>[], 'abc'),
        clearPicked: () async => throw StateError('no such plugin'),
      ).pickAndReadText();
      expect(text, 'abc');
    });

    test('a file of unknown size is read only until it is too large', () async {
      final big = _Unsized(chunks: 256, chunkSize: 4096);
      await expectLater(
        service(
          pick: () async => big,
          clearPicked: () async {},
        ).pickAndReadText(maxBytes: 10000),
        throwsA(isA<FormatException>()),
      );
      expect(big.pulled, lessThanOrEqualTo(10000 + 4096));
    });

    test('a small file of unknown size is read whole', () async {
      final small = _Unsized(chunks: 3, chunkSize: 5);
      final text = await service(
        pick: () async => small,
        clearPicked: () async {},
      ).pickAndReadText(maxBytes: 15);
      expect(text, 'x' * 15);
    });

    test('backing out returns null', () async {
      expect(await service(pick: () async => null).pickAndReadText(), isNull);
    });
  });
}

final class _PickedBytes implements PickedFile {
  _PickedBytes(this.events, this.bytes);
  final List<String> events;
  final Uint8List bytes;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Stream<List<int>> readAsByteStream() {
    events.add('read');
    return Stream.value(bytes);
  }
}

/// A picked file whose size the picker could not tell, read in chunks.
final class _Unsized implements PickedFile {
  _Unsized({required this.chunks, required this.chunkSize});
  final int chunks;
  final int chunkSize;
  int pulled = 0;

  @override
  Future<int?> length() async => null;

  @override
  Stream<List<int>> readAsByteStream() async* {
    for (var i = 0; i < chunks; i++) {
      pulled += chunkSize;
      yield Uint8List.fromList(List.filled(chunkSize, 0x78));
    }
  }
}
