import 'dart:convert';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/data/packs.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/files.dart';
import 'package:daily_tracker/state/actions.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/ui/screens/packs_screen.dart';
import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'harness.dart';

final class _OnePackFile implements FileService {
  _OnePackFile(this.text);
  final String text;
  @override
  Future<String?> pickAndReadText({int maxBytes = 20 * 1024 * 1024}) async =>
      text;
  @override
  Future<void> shareText(
    String fileName,
    String content, {
    String? subject,
    String mimeType = 'application/json',
  }) async {}
}

void main() {
  sqfliteFfiInit();
  setUpAll(loadAppFont);

  testWidgets('a starter pack is added in one go', (tester) async {
    final db = (await tester.runAsync(
      () => openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
        singleInstance: false,
      ),
    ))!;
    addTearDown(() => tester.runAsync(db.close));
    var changes = 0;
    var ids = 0;
    final repo = HabitRepository(db, onChanged: () => changes++);
    final overrides =
        await baseOverrides(
            ledger: Ledger(habits: const [], entries: const []),
          )
          ..add(
            actionsProvider.overrideWithValue(
              HabitActions(
                repo: repo,
                photos: NoPhotos(),
                now: DateTime.now,
                newId: () => 'id${ids++}',
              ),
            ),
          );
    final pack = starterPacks.firstWhere((p) => p.id == 'morning');
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const PacksScreen(openId: 'morning'),
        ),
        GoRoute(path: '/habits', builder: (_, _) => const Text('HABITS')),
      ],
    );
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add ${pack.habits.length} habits'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('HABITS'), findsOneWidget);
    final saved = (await tester.runAsync(repo.habits))!;
    expect(saved.map((h) => h.name), [for (final f in pack.habits) f.name]);
    expect(changes, 1);
  });

  testWidgets(
    'a pack file with a long name and description keeps its Add button on a small screen',
    (tester) async {
      final pack = jsonEncode({
        'format': 'daily-tracker-pack',
        'version': 1,
        'name': 'My coach and I put this routine together over the summer',
        'description': 'Notes from my coach. ' * 15,
        'habits': [
          {'name': 'Stretch'},
        ],
      });
      final overrides = await baseOverrides(ledger: sampleLedger())
        ..add(fileServiceProvider.overrideWithValue(_OnePackFile(pack)));
      final errors = await collectFrameworkErrors(() async {
        await pumpScreen(
          tester,
          const PacksScreen(import: true),
          overrides: overrides,
          textScale: 2,
          size: const Size(360, 640),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
      expect(errors, isEmpty);
      final add = find.text('Add 1 habit');
      expect(add, findsOneWidget);
      expect(tester.getRect(add).bottom, lessThanOrEqualTo(640));
    },
  );
}
