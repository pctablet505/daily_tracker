import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:daily_tracker/app.dart';
import 'package:daily_tracker/data/local/database_helper.dart';
import 'package:daily_tracker/data/repositories/task_repository.dart';
import 'package:daily_tracker/presentation/providers/task_provider.dart';
import 'package:daily_tracker/presentation/providers/update_provider.dart';

void main() {
  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late TaskRepository repository;

  setUpAll(() async {
    _ensureSqlite3Loaded();
    databaseFactory = createDatabaseFactoryFfi(ffiInit: _ensureSqlite3Loaded);
    tempDir = await Directory.systemTemp.createTemp('daily_tracker_widget_test_');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    final dbFile = File(p.join(tempDir.path, 'daily_tracker.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    DatabaseHelper.resetTestDatabasePath();
    DatabaseHelper.setTestDatabasePath(dbFile.path);
    dbHelper = DatabaseHelper();
    repository = TaskRepository(dbHelper);
  });

  tearDown(() async {
    try {
      await dbHelper.close();
    } catch (_) {}
    DatabaseHelper.resetTestDatabasePath();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Daily Tracker App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWithValue(repository),
          updateCheckProvider.overrideWith((ref) => null),
        ],
        child: const DailyTrackerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DailyTrackerApp), findsOneWidget);
  });
}

void _ensureSqlite3Loaded() {
  const candidates = [
    '/home/pctablet505/.cache/bazel/_bazel_pctablet505/c9d4eae62017b0ae004e50f66ccf4980/external/sysroot_linux_x86_64_glibc_2_27/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/lib/x86_64-linux-gnu/libsqlite3.so.0',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      sqlite3_open.open.overrideFor(
        sqlite3_open.OperatingSystem.linux,
        () => DynamicLibrary.open(path),
      );
      return;
    }
  }

  throw StateError(
    'Could not find libsqlite3.so.0. Please install libsqlite3-dev or provide a valid path.',
  );
}
