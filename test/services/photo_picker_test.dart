import 'dart:async';
import 'dart:io';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/photo_picker.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/state/actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

void main() {
  sqfliteFfiInit();
  late SharedPreferences prefs;
  late HabitRepository repo;
  late HabitActions actions;
  late DiskPhotoStore store;
  late File taken;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    repo = HabitRepository(db);
    await repo.addHabit(habit('p', logType: LogType.photo));
    final root = await Directory.systemTemp.createTemp('dt_lost_');
    addTearDown(() => root.delete(recursive: true));
    store = DiskPhotoStore(Directory(p.join(root.path, 'media')));
    actions = HabitActions(
      repo: repo,
      photos: store,
      now: () => DateTime(2026, 10, 11, 9),
      newId: () => 'e1',
    );
    taken = File(p.join(root.path, 'cache', 'image_picker1.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
  });

  Future<void> restart({required Future<String?> Function() lostPhoto}) =>
      recoverLostPhoto(
        prefs,
        lostPhoto: lostPhoto,
        repo: repo,
        actions: actions,
      );

  test(
    'a photo taken while Android stopped the app is logged on the next start',
    () async {
      // The camera is open; the app is stopped before it returns.
      final camera = Completer<String?>();
      unawaited(
        rememberingTarget(prefs, (_) => camera.future)(
          PhotoSource.camera,
          habitId: 'p',
          day: sun,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await restart(lostPhoto: () async => taken.path);
      final e = (await repo.entries()).single;
      expect((e.habitId, e.day), ('p', sun));
      expect(store.fileFor(e.photoPath!).readAsBytesSync(), [1, 2, 3]);

      var askedAgain = false;
      await restart(
        lostPhoto: () async {
          askedAgain = true;
          return taken.path;
        },
      );
      expect(askedAgain, isFalse, reason: 'the record is cleared once used');
    },
  );

  test('a pick that returned forgets its habit, so nothing is logged '
      'twice', () async {
    final pick = rememberingTarget(prefs, (_) async => taken.path);
    expect(await pick(PhotoSource.camera, habitId: 'p', day: sun), taken.path);
    var asked = false;
    await restart(
      lostPhoto: () async {
        asked = true;
        return taken.path;
      },
    );
    expect(asked, isFalse);
    expect(await repo.entries(), isEmpty);
  });

  test('a camera that fails to open forgets its habit too', () async {
    final pick = rememberingTarget(prefs, (_) => throw StateError('none'));
    await expectLater(
      pick(PhotoSource.camera, habitId: 'p', day: sun),
      throwsStateError,
    );
    await restart(lostPhoto: () async => taken.path);
    expect(await repo.entries(), isEmpty);
  });

  test('when Android kept no photo, or the habit is gone, nothing is logged '
      'and the start goes on', () async {
    final camera = Completer<String?>();
    final pick = rememberingTarget(prefs, (_) => camera.future);
    unawaited(pick(PhotoSource.camera, habitId: 'p', day: sun));
    await Future<void>.delayed(Duration.zero);
    await restart(lostPhoto: () async => null);
    expect(await repo.entries(), isEmpty);

    unawaited(pick(PhotoSource.camera, habitId: 'gone', day: sun));
    await Future<void>.delayed(Duration.zero);
    await restart(lostPhoto: () async => taken.path);
    expect(await repo.entries(), isEmpty);

    unawaited(pick(PhotoSource.camera, habitId: 'p', day: sun));
    await Future<void>.delayed(Duration.zero);
    await restart(lostPhoto: () => throw StateError('plugin'));
    expect(await repo.entries(), isEmpty);
  });
}
