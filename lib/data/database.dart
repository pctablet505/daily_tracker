import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const databaseFileName = 'habits.db';
const schemaVersion = 1;

/// Files the first app version left behind. There is no data worth carrying
/// over, so they are deleted rather than migrated.
const _legacyFiles = [
  'daily_tracker.db',
  'daily_tracker.db-journal',
  'daily_tracker.db-wal',
  'daily_tracker.db-shm',
];

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE habits (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      kind TEXT NOT NULL,
      logType TEXT NOT NULL,
      unit TEXT,
      goal REAL,
      daysMask INTEGER NOT NULL,
      dayPart TEXT NOT NULL,
      reminderMinutes INTEGER,
      area TEXT,
      avoidMode TEXT NOT NULL,
      sortOrder INTEGER NOT NULL,
      createdDay TEXT NOT NULL,
      endDay TEXT
    )''');
  await db.execute('''
    CREATE TABLE entries (
      habitId TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
      day TEXT NOT NULL,
      state TEXT NOT NULL,
      value REAL,
      note TEXT,
      photoPath TEXT,
      loggedAt TEXT NOT NULL,
      PRIMARY KEY (habitId, day)
    )''');
  await db.execute('CREATE INDEX entries_by_day ON entries(day)');
  await db.execute('CREATE TABLE seen_days (day TEXT PRIMARY KEY)');
}

/// Opens the app database at [path] (or in memory for `inMemoryDatabasePath`).
///
/// Foreign keys are switched on so an entry can never outlive its habit.
/// With [removeLegacyIn], the first version's database files in that folder
/// are deleted first.
///
/// The phone hands out one shared connection per file by default, so closing it
/// anywhere closes it for the whole app. Code that runs beside the app (a
/// notification button) passes `singleInstance: false` to get, and close, its own.
Future<Database> openAppDatabase(
  DatabaseFactory factory,
  String path, {
  String? removeLegacyIn,
  bool singleInstance = true,
}) async {
  if (removeLegacyIn != null) {
    for (final name in _legacyFiles) {
      final f = File(p.join(removeLegacyIn, name));
      if (f.existsSync()) await f.delete();
    }
  }
  return factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      singleInstance: singleInstance && path != inMemoryDatabasePath,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => _createSchema(db),
    ),
  );
}
