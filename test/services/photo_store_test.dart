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
