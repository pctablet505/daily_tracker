// Regression tests for defects found in review. Each test states the behaviour the app
// promises; a red result is a finding.
import 'dart:io';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/state/actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

void main() {
  sqfliteFfiInit();

  test(
    '"Skip" on a photo day, then "Unskip", does not destroy the photo file',
    () async {
      final db = await openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final tmp = Directory.systemTemp.createTempSync('dt_review_skip_');
      addTearDown(() => tmp.delete(recursive: true));
      final store = DiskPhotoStore(Directory(p.join(tmp.path, 'media')));
      final picked = File(p.join(tmp.path, 'camera.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      var n = 0;
      final act = HabitActions(
        repo: repo,
        photos: store,
        now: () => DateTime.utc(2026, 10, 11, 9),
        newId: () => 'id${n++}',
      );
      final h = await repo.addHabit(habit('ph', logType: LogType.photo));

      await act.logPhoto(h, sat, picked.path);
      final name = (await repo.entries(habitId: 'ph')).single.photoPath!;
      expect(store.fileFor(name).existsSync(), isTrue);

      await act.skip(h, sat); // the Today menu's "Skip"
      await act.skip(h, sat); // and its "Unskip"
      expect(
        store.fileFor(name).existsSync(),
        isTrue,
        reason:
            'the photo file was deleted by Skip; Unskip cannot bring it back '
            '(entry now: ${await repo.entries(habitId: 'ph')})',
      );
    },
  );
}
