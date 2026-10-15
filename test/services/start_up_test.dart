import 'dart:io';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/main.dart';
import 'package:daily_tracker/services/files.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

/// What a start does beside the first screen, with the phone's folders
/// answered here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('a start logs the photo a pick that outlived the app was for, then '
      'tidies the cache, old shares and photos nothing refers to', () async {
    final support = await Directory.systemTemp.createTemp('dt_support_');
    final cache = await Directory.systemTemp.createTemp('dt_cache_');
    addTearDown(() async {
      await support.delete(recursive: true);
      await cache.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => switch (call.method) {
            'getTemporaryDirectory' => cache.path,
            _ => support.path,
          },
        );
    final old = DateTime.now().subtract(const Duration(days: 1));
    final share = File(
      p.join(cache.path, SystemFileService.sharedFolder, 'backup.json'),
    )..createSync(recursive: true);
    share.setLastModifiedSync(old);
    final picked = File(p.join(cache.path, 'picked.jpg'))
      ..writeAsBytesSync([1]);
    final stray = File(p.join(support.path, 'media', 'stray.jpg'))
      ..createSync(recursive: true);
    stray.setLastModifiedSync(old);

    SharedPreferences.setMockInitialValues({'photo.pendingFor': 'p@$mon'});
    final prefs = await SharedPreferences.getInstance();
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        photoStoreProvider.overrideWithValue(await openPhotoStore()),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final repo = c.read(repositoryProvider);
    await repo.addHabit(habit('p', logType: LogType.photo));

    await startServices(c, prefs, lostPhoto: () async => picked.path);

    final logged = (await repo.entries()).single.photoPath;
    expect(logged, isNotNull);
    expect(File(p.join(support.path, 'media', logged)).existsSync(), isTrue);
    expect(picked.existsSync(), isFalse, reason: 'the cache copy is tidied');
    expect(stray.existsSync(), isFalse);
    expect(share.existsSync(), isFalse);
  });
}
