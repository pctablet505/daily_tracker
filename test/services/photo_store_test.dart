import 'dart:io';

import 'package:daily_tracker/services/photo_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory media;
  late File source;
  late DiskPhotoStore store;
  var n = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dt_photo_');
    media = Directory(p.join(root.path, 'media'));
    source = File(p.join(root.path, 'cache', 'scaled_123.JPG'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    n = 0;
    store = DiskPhotoStore(media, newId: () => 'id${n++}');
    addTearDown(() => root.delete(recursive: true));
  });

  test(
    'exists is true for a stored photo, false once it is gone or never was',
    () async {
      final name = await store.importFile(source.path);
      expect(store.exists(name), isTrue);
      await store.delete(name);
      expect(store.exists(name), isFalse);
      expect(store.exists('never-stored.jpg'), isFalse);
    },
  );

  test(
    'exists asks the disk once per name; import and delete keep it current',
    () async {
      final file = File(p.join(media.path, 'id0.jpg'));
      expect(store.exists('id0.jpg'), isFalse);
      file.createSync(recursive: true);
      expect(
        store.exists('id0.jpg'),
        isFalse,
        reason: 'the first answer is kept',
      );

      final name = await store.importFile(source.path);
      expect(name, 'id0.jpg');
      expect(store.exists(name), isTrue);
      file.deleteSync();
      expect(store.exists(name), isTrue, reason: 'the import answered it');

      await store.delete(name);
      expect(store.exists(name), isFalse);
    },
  );

  test(
    'exists says false, not an error, for a name that could leave the folder',
    () {
      for (final bad in ['../x.jpg', '/etc/passwd', '', '.hidden', 'a/b.jpg']) {
        expect(store.exists(bad), isFalse, reason: bad);
      }
    },
  );

  test('copies the photo into the media folder and returns its name', () async {
    final name = await store.importFile(source.path);
    expect(name, 'id0.jpg');
    expect(store.fileFor(name).readAsBytesSync(), [1, 2, 3, 4]);
    expect(p.dirname(store.fileFor(name).path), media.path);
  });

  test('the photo survives the source being deleted (cache cleared)', () async {
    final name = await store.importFile(source.path);
    source.deleteSync();
    expect(store.fileFor(name).existsSync(), isTrue);
  });

  test('two photos get two names', () async {
    expect(
      await store.importFile(source.path),
      isNot(await store.importFile(source.path)),
    );
  });

  test('a source with no usable extension is stored as .jpg', () async {
    final bare = File(p.join(root.path, 'cache', 'photo'))
      ..writeAsBytesSync([9]);
    expect(await store.importFile(bare.path), endsWith('.jpg'));
  });

  test('delete removes the file, and a name already gone is fine', () async {
    final name = await store.importFile(source.path);
    await store.delete(name);
    expect(store.fileFor(name).existsSync(), isFalse);
    await store.delete(name);
  });

  test('a name that would leave the photo folder is refused', () {
    for (final bad in ['../x.jpg', 'a/b.jpg', '', '.hidden', '/etc/passwd']) {
      expect(() => store.fileFor(bad), throwsArgumentError, reason: bad);
    }
  });

  test('the picker\'s copy in the app cache is removed once stored; a file elsewhere stays', () async {
    final tidy = DiskPhotoStore(
      media,
      newId: () => 'id${n++}',
      cache: Directory(p.join(root.path, 'cache')),
    );
    final name = await tidy.importFile(source.path);
    expect(tidy.fileFor(name).readAsBytesSync(), [1, 2, 3, 4]);
    expect(source.existsSync(), isFalse);

    // Next to the cache, not in it: a name that only starts the same.
    final mine = File(p.join(root.path, 'cache-other', 'mine.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([5]);
    await tidy.importFile(mine.path);
    expect(mine.existsSync(), isTrue);
  });

  test(
    'lists each stored photo with when it was written, and nothing else',
    () async {
      expect(await store.listStored(), isEmpty, reason: 'no folder yet');
      final name = await store.importFile(source.path);
      final when = DateTime(2026, 10, 1, 8);
      store.fileFor(name).setLastModifiedSync(when);
      File(p.join(media.path, '.nomedia')).createSync();
      Directory(p.join(media.path, 'sub')).createSync();
      expect(await store.listStored(), {name: when});
    },
  );

  test(
    'importing a file that does not exist fails and leaves nothing behind',
    () async {
      await expectLater(
        store.importFile(p.join(root.path, 'nope.jpg')),
        throwsA(isA<FileSystemException>()),
      );
      expect(media.existsSync() ? media.listSync() : [], isEmpty);
    },
  );
}
