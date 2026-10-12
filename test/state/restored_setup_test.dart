import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/state/restored_setup.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

/// Android's cloud backup puts the habits back on a new phone but not the settings, so the
/// phone has habits and no record that the first-run screen was done.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late HabitRepository repo;

  setUp(() async {
    final db = await openAppDatabase(factory, inMemoryDatabasePath);
    repo = HabitRepository(db);
    addTearDown(db.close);
  });

  Future<SharedPreferences> prefs([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    return SharedPreferences.getInstance();
  }

  test('a phone with habits and no settings counts as set up', () async {
    await repo.addHabit(habit('a'));
    final p = await prefs();
    expect(Settings.read(p).onboardingDone, isFalse);

    await markSetUpIfHabitsExist(repo, p);

    expect(Settings.read(p).onboardingDone, isTrue);
  });

  test(
    'a fresh install with no habits still shows the first-run screen',
    () async {
      final p = await prefs();

      await markSetUpIfHabitsExist(repo, p);

      expect(Settings.read(p).onboardingDone, isFalse);
    },
  );

  test('archived habits are enough to show the app was used', () async {
    await repo.addHabit(habit('old', end: wed));
    final p = await prefs();

    await markSetUpIfHabitsExist(repo, p);

    expect(Settings.read(p).onboardingDone, isTrue);
  });

  test('it changes nothing but that flag', () async {
    await repo.addHabit(habit('a'));
    final p = await prefs();
    await const Settings(theme: ThemeChoice.dark, streakThreshold: 80).write(p);
    final before = Settings.read(p);

    await markSetUpIfHabitsExist(repo, p);

    expect(
      Settings.read(p),
      before.copyWith(onboardingDone: true),
      reason: 'theme and streak share must survive',
    );
  });

  test(
    'a database that cannot be read does not stop the app starting',
    () async {
      final broken = await openAppDatabase(factory, inMemoryDatabasePath);
      await broken.close();
      final p = await prefs();

      await markSetUpIfHabitsExist(HabitRepository(broken), p);

      expect(Settings.read(p).onboardingDone, isFalse);
    },
  );

  test('a phone already set up is left alone', () async {
    final p = await prefs({'onboardingDone': true, 'theme': 'dark'});
    final before = Settings.read(p);

    await markSetUpIfHabitsExist(repo, p);

    expect(Settings.read(p), before);
  });
}
