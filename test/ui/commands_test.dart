import 'dart:io';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/ui/commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

final class _SpyPhotos implements PhotoStore {
  final deleted = <String>[];
  @override
  Future<String> importFile(String sourcePath) async => 'x.jpg';
  @override
  File fileFor(String name) => File('/nowhere/$name');
  @override
  bool exists(String name) => true;
  @override
  Future<Map<String, DateTime>> listStored() async => {};
  @override
  Future<void> delete(String name) async => deleted.add(name);
}

void main() {
  sqfliteFfiInit();

  testWidgets('the delete Undo closes after its 6 s and the photos then go', (
    tester,
  ) async {
    // Deleting a photo first asks where the safety copies are: a documents folder with none.
    final support = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('dt_cmd_'),
    ))!;
    addTearDown(() => tester.runAsync(() => support.delete(recursive: true)));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => support.path,
        );
    final db = (await tester.runAsync(
      () => openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath),
    ))!;
    addTearDown(() => tester.runAsync(db.close));
    final h = habit('photo', logType: LogType.photo);
    await tester.runAsync(() async {
      final repo = HabitRepository(db);
      await repo.addHabit(h);
      await repo.setEntry(
        entry('photo', mon).copyWith(photoPath: () => 'p1.jpg'),
      );
    });
    final photos = _SpyPhotos();
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(sp),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 11, 9)),
          databaseProvider.overrideWithValue(db),
          photoStoreProvider.overrideWithValue(photos),
          appVersionProvider.overrideWith((ref) async => '2.0.0'),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                return const Text('home');
              },
            ),
          ),
        ),
      ),
    );
    final deleting = confirmAndDeleteHabit(
      tester.element(find.text('home')),
      widgetRef,
      h,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.runAsync(() => deleting);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Deleted ${h.name}'), findsOneWidget);

    // One frame a second: the 6 s start only once the snackbar is fully shown.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    // Let the clean-up's file and database work finish.
    // The clean-up hops between real file and database work and the test's fake clock, so
    // alternate letting the real work run and pumping what it left behind.
    for (var i = 0; i < 50 && photos.deleted.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('Deleted ${h.name}'), findsNothing);
    expect(photos.deleted, ['p1.jpg']);
  });
}
