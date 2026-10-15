// Regression tests for the 43 adversarial review findings (Issue #4 / PR #5).
import 'dart:convert';
import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/logic/habit_detail.dart';
import 'package:daily_tracker/logic/habit_form.dart';
import 'package:daily_tracker/logic/logging.dart';
import 'package:daily_tracker/logic/progress_view.dart';
import 'package:daily_tracker/logic/today_view.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/services/lock.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/services/updater.dart';
import 'package:daily_tracker/state/actions.dart';
import 'package:daily_tracker/state/lock_controller.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:daily_tracker/state/update_prompt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import '../services/lock_test.dart' show FakeBiometrics;

void main() {
  sqfliteFfiInit();

  group('Lock & Security regressions', () {
    test('unlockWithBiometrics refuses when settings.lockBiometric is false', () async {
      final now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = LockService(
        prefs: prefs,
        biometrics: FakeBiometrics()
          ..available = true
          ..result = true,
        now: () => now,
      );
      await lock.setPin('1234');
      await const Settings(
        lockOn: true,
        lockBiometric: false,
      ).write(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          lockServiceProvider.overrideWithValue(lock),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(lockedProvider.notifier);
      expect(c.read(lockedProvider), isTrue);
      final ok = await n.unlockWithBiometrics();
      expect(ok, isFalse);
      expect(c.read(lockedProvider), isTrue);
    });

    test('unlocking clears stale _pausedAt so next resumed() does not relock', () async {
      var now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = LockService(
        prefs: prefs,
        biometrics: FakeBiometrics(),
        now: () => now,
      );
      await lock.setPin('1234');
      await const Settings(lockOn: true, lockAfterSeconds: 60).write(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          lockServiceProvider.overrideWithValue(lock),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');
      n.paused();
      now = now.add(const Duration(minutes: 10));
      n.lockNow();
      expect(c.read(lockedProvider), isTrue);
      await n.unlockWithPin('1234');
      expect(c.read(lockedProvider), isFalse);
      // Subsequent resumed() without an intervening pause must not re-lock!
      n.resumed();
      expect(c.read(lockedProvider), isFalse);
    });

    test('fire-and-forget runExternal grants external grace when paused() follows closely', () async {
      var now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = LockService(
        prefs: prefs,
        biometrics: FakeBiometrics(),
        now: () => now,
      );
      await lock.setPin('1234');
      await const Settings(lockOn: true, lockAfterSeconds: 0).write(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          lockServiceProvider.overrideWithValue(lock),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(lockedProvider.notifier);
      await n.unlockWithPin('1234');

      // Fire-and-forget intent returns before Android pauses the activity.
      await n.runExternal(() async => true);
      now = now.add(const Duration(milliseconds: 100));
      n.paused();
      now = now.add(const Duration(seconds: 30));
      n.resumed();
      expect(
        c.read(lockedProvider),
        isFalse,
        reason: 'returning from external intent within 5 min should not lock',
      );
    });

    test('LockService.remainingWait persists clamped lockout across clock rollback', () async {
      var now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = LockService(
        prefs: prefs,
        biometrics: FakeBiometrics(),
        now: () => now,
      );
      await lock.setPin('1234');
      // 5 wrong attempts at future clock (+10 days) -> 30s lockout at +10d00m30s.
      now = now.add(const Duration(days: 10));
      for (var i = 0; i < 5; i++) {
        await lock.checkPin('9999');
      }
      expect(lock.remainingWait, const Duration(seconds: 30));

      // Clock rolls back by 10 days; remainingWait clamps to 30s AND persists.
      now = now.subtract(const Duration(days: 10));
      expect(lock.remainingWait, const Duration(seconds: 30));
      // After 31s at real time, lockout expires cleanly instead of looping forever.
      now = now.add(const Duration(seconds: 31));
      expect(lock.remainingWait, Duration.zero);
    });

    test('UpdatePrompter handles clock rollback and releaseToOffer(recordOffer: false)', () async {
      var now = DateTime.utc(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const rel = ReleaseInfo(
        version: '2.0.0',
        notes: 'n',
        apkUrl: 'https://example.com/a.apk',
      );
      final prompter = UpdatePrompter(
        prefs: prefs,
        now: () => now,
        check: () async => const UpdateAvailable(rel),
        isOnWifi: () async => true,
        isOnline: () async => true,
        wifiOnly: () => false,
      );

      final first = await prompter.releaseToOffer(recordOffer: false);
      expect(first?.version, '2.0.0');

      // Advance past 12h check throttle; since recordOffer was false, it is still offered.
      now = now.add(const Duration(hours: 13));
      final second = await prompter.releaseToOffer(recordOffer: false);
      expect(second?.version, '2.0.0');
      await prompter.markOffered('2.0.0');

      // Clock rolls back 5 days -> should not permanently block checks/offers.
      now = now.subtract(const Duration(days: 5));
      final afterRollback = await prompter.releaseToOffer(recordOffer: false);
      expect(afterRollback?.version, '2.0.0');
    });
  });

  group('Data, Validation & Stats regressions', () {
    test('DayKey.tryParse rejects year 0000', () {
      expect(DayKey.tryParse('0000-01-01'), isNull);
      expect(DayKey.tryParse('0001-01-01'), const DayKey(1, 1, 1));
    });

    test('Habit.fromMap and Entry.fromMap reject invalid fields', () {
      final validHabit = habit('a').toMap();
      expect(
        () => Habit.fromMap({...validHabit, 'goal': 0}),
        throwsFormatException,
      );
      expect(
        () => Habit.fromMap({...validHabit, 'daysMask': 0}),
        throwsFormatException,
      );
      expect(
        () => Habit.fromMap({...validHabit, 'sortOrder': 1.5}),
        throwsFormatException,
      );
      expect(
        () => Habit.fromMap({...validHabit, 'endDay': '1999-01-01'}),
        throwsFormatException,
      );
      expect(
        Habit.fromMap({...validHabit, 'reminderMinutes': 1440}).reminderMinutes,
        isNull,
      );

      final validEntry = entry('a', mon).toMap();
      expect(
        () => Entry.fromMap({...validEntry, 'value': -1}),
        throwsFormatException,
      );
      expect(
        () => Entry.fromMap({...validEntry, 'loggedAt': 'not-a-date'}),
        throwsFormatException,
      );
    });

    test('decodeBackup rejects version < 1 and non-Map settings', () {
      final base = {
        'format': backupFormat,
        'version': 0,
        'exportedAt': '2026-10-11T00:00:00.000Z',
        'habits': <Object?>[],
        'entries': <Object?>[],
        'seenDays': <String>[],
      };
      expect(() => decodeBackup(jsonEncode(base)), throwsFormatException);
      expect(
        () => decodeBackup(jsonEncode({...base, 'version': 1, 'settings': 'bad'})),
        throwsFormatException,
      );
    });

    test('summarizeDay and habitRate ignore entries outside active date range', () {
      final h = habit('a', created: wed, end: fri);
      final l = Ledger(
        habits: [h],
        entries: [
          entry('a', mon), // before createdDay
          entry('a', wed), // active
          entry('a', sun), // after endDay
        ],
      );
      expect(summarizeDay(l, mon).done, 0);
      expect(summarizeDay(l, sun).done, 0);
      expect(habitRate(l, h, mon, sun).fraction, closeTo(1 / 3, 1e-6));
    });

    test('unscheduled partial entry increments planned and is not marked DotState.none', () {
      final h = habit(
        'n',
        created: mon,
        mask: Habit.weekdaysOnly,
        logType: LogType.number,
        goal: 10,
      );
      // Saturday is unscheduled, user logs 5/10 (partial).
      final l = Ledger(
        habits: [h],
        entries: [
          Entry(
            habitId: 'n',
            day: sat,
            state: EntryState.partial,
            value: 5,
            loggedAt: DateTime.utc(2026, 10, 10),
          ),
        ],
      );
      final sum = summarizeDay(l, sat);
      expect(sum.planned, 1);
      expect(sum.done, 0);
      final detail = buildHabitDetail(l, h, sun);
      final satDot = detail.recentDays.firstWhere((d) => d.day == sat);
      expect(satDot.state, DotState.missed);
    });

    test('skipEntry unskips tracksSlips and non-number habits with leftover value', () {
      final sc = stayClear('s');
      final skippedSlip = Entry(
        habitId: 's',
        day: mon,
        state: EntryState.skipped,
        loggedAt: DateTime.utc(2026, 10, 5),
      );
      expect(skipEntry(sc, mon, skippedSlip, DateTime.utc(2026, 10, 5)), isNull);
      final skippedSlipWithNote = Entry(
        habitId: 's',
        day: mon,
        state: EntryState.skipped,
        note: 'oops',
        loggedAt: DateTime.utc(2026, 10, 5),
      );
      expect(
        skipEntry(sc, mon, skippedSlipWithNote, DateTime.utc(2026, 10, 5))?.state,
        EntryState.slipped,
      );

      final booleanHabit = habit('b', goal: 10);
      final skippedWithVal = Entry(
        habitId: 'b',
        day: mon,
        state: EntryState.skipped,
        value: 5,
        loggedAt: DateTime.utc(2026, 10, 5),
      );
      expect(
        skipEntry(booleanHabit, mon, skippedWithVal, DateTime.utc(2026, 10, 5))?.state,
        EntryState.done,
      );
    });

    test('slipEntry preserves value and photoPath', () {
      final sc = stayClear('s');
      final current = Entry(
        habitId: 's',
        day: mon,
        state: EntryState.done,
        value: 3,
        photoPath: 'p.jpg',
        loggedAt: DateTime.utc(2026, 10, 5),
      );
      final slipped = slipEntry(sc, mon, current, DateTime.utc(2026, 10, 5));
      expect(slipped?.state, EntryState.slipped);
      expect(slipped?.value, 3);
      expect(slipped?.photoPath, 'p.jpg');
    });

    test('archived habit streak is 0 when today is after endDay and endDay was missed', () {
      final h = habit('a', created: mon, end: thu);
      final l = Ledger(
        habits: [h],
        entries: [entry('a', mon), entry('a', tue), entry('a', wed)],
      );
      expect(habitStreak(l, h, fri).current, 0);
      expect(habitStreak(l, h, fri).best, 3);
    });

    test('rateOver and heatLevel account for stay-clear habits and slips', () {
      final sc = stayClear('s', created: mon);
      final cleanLedger = Ledger(habits: [sc], entries: const [], seenDays: [mon]);
      expect(rateOver(cleanLedger, mon, mon).fraction, 1.0);

      final slipLedger = Ledger(
        habits: [habit('a', created: mon), sc],
        entries: [entry('a', mon), slip('s', mon)],
        seenDays: [mon],
      );
      expect(heatLevel(summarizeDay(slipLedger, mon), isFuture: false), HeatLevel.mid);
    });

    test('buildHabitDetail anchors to endDay for archived habits and tracks totalSlips', () {
      final h = stayClear('s', created: mon, end: wed);
      final l = Ledger(
        habits: [h],
        entries: [slip('s', tue), slip('s', fri)],
      );
      final detail = buildHabitDetail(l, h, sun);
      expect(detail.recentDays.last.day, wed);
      expect(detail.totalSlips, 1);
    });

    test('buildTodayView sets hasAnyHabit true on past day with archived habit', () {
      final h = habit('a', created: mon, end: wed);
      final l = Ledger(habits: [h], entries: const []);
      expect(buildTodayView(l, tue).hasAnyHabit, isTrue);
    });
  });

  group('Reminders, Backup, Updater & Photos regressions', () {
    test('planReminders(includeCarryOver: true) keeps quiet-hours carry-over from yesterday', () {
      const yesterday = DayKey(2026, 10, 10);
      const today = DayKey(2026, 10, 11);
      final read = habit(
        'read',
        created: yesterday.addDays(-7),
      ).copyWith(reminderMinutes: () => 23 * 60);

      final plan = planReminders(
        Ledger(habits: [read], entries: const []),
        settings: const Settings(
          eveningCheckInOn: false,
          quietHoursOn: true,
          quietStartMinutes: 22 * 60,
          quietEndMinutes: 7 * 60,
        ),
        now: DateTime(today.year, today.month, today.day, 1),
        horizonDays: 1,
        includeCarryOver: true,
      );
      expect(
        plan.any((r) => r.payload == 'habit:read@$yesterday'),
        isTrue,
      );
    });

    test('markDoneFromNotification ignores tracksSlips and archived habits', () async {
      final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final repo = HabitRepository(db);
      await repo.addHabit(stayClear('sc', created: mon));
      await repo.addHabit(habit('arch', created: mon, end: tue));

      await markDoneFromNotification(
        db,
        'sc',
        wed,
        DateTime.utc(2026, 10, 7),
      );
      await markDoneFromNotification(
        db,
        'arch',
        wed,
        DateTime.utc(2026, 10, 7),
      );
      expect(await repo.entries(), isEmpty);
    });

    test('BackupService.exportCsv sanitizes newline formula injection and BackupService.undoLastRestore refuses a corrupt newest copy', () async {
      final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final h = await repo.addHabit(habit('h1'));
      await repo.setEntry(
        Entry(
          habitId: h.id,
          day: mon,
          state: EntryState.done,
          note: '\n=CMD()',
          loggedAt: DateTime.utc(2026, 10, 5),
        ),
      );
      final safety = Directory.systemTemp.createTempSync('dt_adv_safe_');
      addTearDown(() => safety.delete(recursive: true));
      final svc = BackupService(
        repo: repo,
        readSettings: () => const Settings(),
        applySettings: (_) async {},
        safetyDir: () async => safety,
        now: () => DateTime.utc(2026, 10, 11, 12),
        appVersion: () async => '2.0.0',
      );
      final csv = await svc.exportCsv();
      expect(csv.text, contains("'\n=CMD()"));

      // Write a valid older safety copy and a newer corrupt one.
      final validJson = await svc.encodeForUpload();
      final f1 = File(p.join(safety.path, 'before-restore-2026-10-10.json'))
        ..writeAsStringSync(validJson);
      f1.setLastModifiedSync(DateTime.utc(2026, 10, 10));
      final f2 = File(p.join(safety.path, 'before-restore-2026-10-11.json'))
        ..writeAsStringSync('{corrupt');
      f2.setLastModifiedSync(DateTime.utc(2026, 10, 11));

      await repo.deleteHabit('h1');
      expect(await repo.habits(), isEmpty);
      await expectLater(svc.undoLastRestore(), throwsFormatException);
      expect(await repo.habits(), isEmpty);
    });

    test('parseRelease refuses non-HTTPS apkUrl and strips non-HTTPS sha256Url', () {
      expect(
        parseRelease({
          'tag_name': 'v2.0.0',
          'body': 'notes',
          'assets': [
            {
              'name': 'app-release.apk',
              'browser_download_url': 'http://insecure.example.com/app.apk',
              'size': 1000,
            },
          ],
        }),
        isNull,
      );
      final rel = parseRelease({
        'tag_name': 'v2.0.0',
        'body': 'notes',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://secure.example.com/app.apk',
            'size': 1000,
          },
          {
            'name': 'app-release.apk.sha256',
            'browser_download_url': 'http://insecure.example.com/app.apk.sha256',
            'size': 64,
          },
        ],
      });
      expect(rel, isNotNull);
      expect(rel!.sha256Url, isNull);
    });

    test('DiskPhotoStore sanitizes extensions and HabitActions preserves shared photos', () async {
      final tmp = Directory.systemTemp.createTempSync('dt_adv_photo_');
      addTearDown(() => tmp.delete(recursive: true));
      final store = DiskPhotoStore(
        Directory(p.join(tmp.path, 'photos')),
        newId: () => 'p1',
      );
      final weird = File(p.join(tmp.path, 'bad.extensiontoolong'))
        ..writeAsBytesSync([1, 2, 3]);
      final savedName = await store.importFile(weird.path);
      expect(savedName, 'p1.jpg');

      final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final h = await repo.addHabit(habit('ph', logType: LogType.photo));
      // Two entries share p1.jpg (e.g., from a restored backup).
      await repo.setEntry(
        Entry(
          habitId: h.id,
          day: mon,
          state: EntryState.done,
          photoPath: savedName,
          loggedAt: DateTime.utc(2026, 10, 5),
        ),
      );
      await repo.setEntry(
        Entry(
          habitId: h.id,
          day: tue,
          state: EntryState.done,
          photoPath: savedName,
          loggedAt: DateTime.utc(2026, 10, 6),
        ),
      );
      final replacement = File(p.join(tmp.path, 'new.png'))
        ..writeAsBytesSync([4, 5, 6]);
      final store2 = DiskPhotoStore(
        Directory(p.join(tmp.path, 'photos')),
        newId: () => 'p2',
      );
      final act = HabitActions(
        repo: repo,
        photos: store2,
        now: () => DateTime.utc(2026, 10, 6),
        newId: () => 'p2',
      );
      await act.logPhoto(h, tue, replacement.path);
      expect(
        store2.fileFor(savedName).existsSync(),
        isTrue,
        reason: 'mon still references p1.jpg so replacing tue must not delete it',
      );
    });

    test('HabitForm.goalError rejects goals with >2 decimal places', () {
      const f = HabitForm(
        name: 'Run',
        logType: LogType.number,
        goalText: '1.234',
      );
      expect(f.goalError, isNotNull);
      expect(f.isValid, isFalse);
    });
  });
}
