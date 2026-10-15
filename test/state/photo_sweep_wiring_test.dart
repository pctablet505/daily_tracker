import 'dart:io';

import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 11, 12);

  test('a restore in the app removes photos nothing refers to, and keeps those its safety copy needs', () async {
    final support = await Directory.systemTemp.createTemp('dt_support_');
    addTearDown(() => support.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => support.path,
        );
    SharedPreferences.setMockInitialValues({});
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    final media = Directory(p.join(support.path, 'media'))..createSync();
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        photoStoreProvider.overrideWithValue(DiskPhotoStore(media)),
        clockProvider.overrideWithValue(() => now),
        appVersionProvider.overrideWith((ref) async => '2.0.0'),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    File photo(String name) => File(p.join(media.path, name))
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(now.subtract(const Duration(days: 1)));
    final mine = photo('mine.jpg');
    final stray = photo('stray.jpg');
    final repo = c.read(repositoryProvider);
    await repo.addHabit(habit('p', logType: LogType.photo));
    await repo.setEntry(entry('p', mon).copyWith(photoPath: () => 'mine.jpg'));

    await c
        .read(backupServiceProvider)
        .restore(
          encodeBackup(
            Snapshot(
              habits: [habit('q', logType: LogType.photo)],
              entries: [],
              seenDays: {},
            ),
            now: now,
            appVersion: '2.0.0',
          ),
        );
    expect(stray.existsSync(), isFalse);
    expect(mine.existsSync(), isTrue);

    // The restored data gets the same photo, and the user clears it again.
    final q = (await repo.habits()).single;
    await repo.setEntry(entry('q', mon).copyWith(photoPath: () => 'mine.jpg'));
    await c.read(actionsProvider).clear(q, mon);
    expect(mine.existsSync(), isTrue, reason: 'Undo the restore needs it');
  });
}
