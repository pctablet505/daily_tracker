import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

void main() {
  sqfliteFfiInit();
  late HabitRepository repo;
  late Database db;
  final now = DateTime.utc(2026, 10, 11, 8);

  setUp(() async {
    db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    repo = HabitRepository(db);
    addTearDown(db.close);
  });

  test('the Done button on a notification marks a tick habit done', () async {
    await repo.addHabit(habit('a'));
    expect(await markDoneFromNotification(db, 'a', sun, now), isTrue);
    final e = (await repo.entries()).single;
    expect(
      (e.habitId, e.day, e.state, e.loggedAt),
      ('a', sun, EntryState.done, now),
    );
  });

  test('pressing it twice does not undo it', () async {
    await repo.addHabit(habit('a'));
    await markDoneFromNotification(db, 'a', sun, now);
    expect(await markDoneFromNotification(db, 'a', sun, now), isTrue);
    expect((await repo.entries()).single.state, EntryState.done);
  });

  test('a skipped day becomes done', () async {
    await repo.addHabit(habit('a'));
    await repo.setEntry(entry('a', sun, EntryState.skipped));
    await markDoneFromNotification(db, 'a', sun, now);
    expect((await repo.entries()).single.state, EntryState.done);
  });

  test('a number habit or an unknown habit is left alone', () async {
    await repo.addHabit(habit('n', logType: LogType.number));
    expect(await markDoneFromNotification(db, 'n', sun, now), isFalse);
    expect(await markDoneFromNotification(db, 'ghost', sun, now), isFalse);
    expect(await repo.entries(), isEmpty);
  });
}
