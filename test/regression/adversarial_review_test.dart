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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import '../services/lock_test.dart' show FakeBiometrics;

void main() {
  sqfliteFfiInit();

  group('Lock & Security regressions', () {
    test('unlockWithBiometrics refuses when settings.lockBiometric is false', () async {
      var now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = LockService(
        prefs: prefs,
        biometrics: FakeBiometrics(available: true, allow: true),
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
        await lock.verifyPin('9999');
      }
      expect(lock.remainingWait(), const Duration(seconds: 30));

      // Clock rolls back by 10 days; remainingWait clamps to 300s AND persists.
      now = now.subtract(const Duration(days: 10));
      expect(lock.remainingWait(), const Duration(seconds: 300));
      // Even after 301s, lockout expires cleanly.
      now = now.add(const Duration(seconds: 301));
      expect(lock.remainingWait(), Duration.zero);
    });

    test('UpdatePromptLimiter handles clock rollback and releaseToOffer(recordOffer: false)', () async {
      var now = DateTime(2026, 10, 11, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final limiter = UpdatePromptLimiter(prefs, now: () => now);

      expect(limiter.tryClaimCheck(), isTrue);
      await limiter.releaseToOffer(recordOffer: false);
      expect(
        limiter.shouldOffer('2.0.0'),
        isTrue,
        reason: 'suppressed offer must not start 24h cooldown',
      );
      await limiter.markOffered();
      expect(limiter.shouldOffer('2.0.0'), isFalse);

      // Clock rolls back 2 days -> should not permanently block checks/offers.
      now = now.subtract(const Duration(days: 2));
      expect(limiter.tryClaimCheck(), isTrue);
      await limiter.releaseToOffer(recordOffer: false);
      expect(limiter.shouldOffer('2.0.0'), isTrue);
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
        () => Habit.fromMap({...validHabit, 'logType': 'bogus'}),
        throwsFormatException,
      );
      expect(
        () => Habit.fromMap({...validHabit, 'goal': 0}),
        throwsFormatException,
      );
      expect(
        () => Habit.fromMap({...validHabit, 'daysMask': 0}),
        throwsFormatException,
      );
      expect(
        () => Habit.fromMap({...validHabit, 'reminderMinutes': 1440}),
        throwsFormatException,
      );
      expect(
        () => Habit.fromMap({...validHabit, 'sortOrder': 1.5}),
        throwsFormatException,
      );

      final validEntry = entry('a', mon).toMap();
      expect(
        () => Entry.fromMap({...validEntry, 'state': 'bogus'}),
        throwsFormatException,
      );
      expect(
        () => Entry.fromMap({...validEntry, 'value': -1}),
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
      expect(habitRate(l, h, mon, sun), closeTo(1 / 3, 1e-6));
    });

    test('unscheduled partial entry increments planned and is not marked rest', () {
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
      expect(sum.partial, 1);
      final detail = habitDetail(l, h, sat);
      final satRecord = detail.recentDays.firstWhere((d) => d.day == sat);
      expect(satRecord.mark, DayMark.partial);
    });

    test('skipEntry unskips tracksSlips and boolean habits with leftover value', () {
      final sc = stayClear('s');
      final skippedSlip = Entry(
        habitId: 's',
        day: mon,
        state: EntryState.skipped,
        loggedAt: DateTime.utc(2026, 10, 5),
      );
      expect(skipEntry(sc, mon, skippedSlip, DateTime.utc(2026, 10, 5)), isNull);

      final booleanHabit = habit('b');
      final skippedWithVal = Entry(
        habitId: 'b',
        day: mon,
        state: EntryState.skipped,
        value: 5,
        loggedAt: DateTime.utc(2026, 10, 5),
      );
      expect(
        skipEntry(booleanHabit, mon, skippedWithVal, DateTime.utc(2026, 10, 5)),
        isNull,
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
      expect(slipped?.state, EntryState.slip);
      expect(slipped?.value, 3);
      expect(slipped?.photoPath, 'p.jpg');
    });

    test('archived habit streak is 0 when today is after endDay', () {
      final h = habit('a', created: mon, end: wed);
      final l = Ledger(
        habits: [h],
        entries: [entry('a', mon), entry('a', tue), entry('a', wed)],
      );
      expect(habitStreak(l, h, wed).current, 3);
      expect(habitStreak(l, h, fri).current, 0);
      expect(habitStreak(l, h, fri).best, 3);
    });

    test('rateOver and heatLevel account for stay-clear habits and slips', () {
      final sc = stayClear('s', created: mon);
      final cleanLedger = Ledger(habits: [sc], entries: const [], seenDays: [mon]);
      expect(rateOver(cleanLedger, mon, mon), 1.0);

      final slipLedger = Ledger(
        habits: [habit('a', created: mon), sc],
        entries: [entry('a', mon), slip('s', mon)],
        seenDays: [mon],
      );
      expect(heatLevel(summarizeDay(slipLedger, mon)), HeatLevel.mid);
    });

    test('habitDetail anchors to endDay for archived habits and tracks totalSlips', () {
      final h = stayClear('s', created: mon, end: wed);
      final l = Ledger(
        habits: [h],
        entries: [slip('s', tue), slip('s', fri)],
      );
      final detail = habitDetail(l, h, sun);
      expect(detail.recentDays.first.day, wed);
      expect(detail.totalSlips, 1);
    });

    test('todayView sets hasAnyHabit true on past day with archived habit', () {
      final h = habit('a', created: mon, end: wed);
      final l = Ledger(habits: [h], entries: const []);
      expect(todayView(l, tue, sun).hasAnyHabit, isTrue);
    });
  });

  group('Reminders, Backup, Updater & Photos regressions', () {
    test('planReminders(includeCarryOver: true) keeps quiet-hours carry-over from yesterday', () {
      final yesterday = const DayKey(2026, 10, 10);
      final today = const DayKey(2026, 10, 11);
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
        repo,
        const HabitPayload('sc', wed),
        now: DateTime.utc(2026, 10, 7),
      );
      await markDoneFromNotification(
        repo,
        const HabitPayload('arch', wed),
        now: DateTime.utc(2026, 10, 7),
      );
      expect(await repo.entries(), isEmpty);
    });

    test('BackupService.exportCsv sanitizes newline formula injection and BackupService.undoLastRestore skips corrupt files', () async {
      final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final h = await repo.addHabit(habit('h1'));
      await repo.putEntry(
        Entry(
          habitId: h.id,
          day: mon,
          state: EntryState.done,
          note: 'line1\n=CMD()',
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
      expect(csv, contains('\n\'=CMD()'));

      // Write a valid older safety copy and a newer corrupt one.
      final validJson = await svc.exportJson();
      final f1 = File(p.join(safety.path, 'before-restore-2026-10-10.json'))
        ..writeAsStringSync(validJson);
      f1.setLastModifiedSync(DateTime.utc(2026, 10, 10));
      final f2 = File(p.join(safety.path, 'before-restore-2026-10-11.json'))
        ..writeAsStringSync('{corrupt');
      f2.setLastModifiedSync(DateTime.utc(2026, 10, 11));

      await repo.deleteHabit('h1');
      expect(await repo.habits(), isEmpty);
      final summary = await svc.undoLastRestore();
      expect(summary, isNotNull);
      expect(summary!.habits, 1);
    });

    test('UpdateChecker refuses non-HTTPS apkUrl', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v9.9.9',
            'body': 'notes',
            'assets': [
              {
                'name': 'app-release.apk',
                'browser_download_url': 'http://insecure.example.com/app.apk',
                'size': 1000,
              },
            ],
          }),
          200,
        );
      });
      final checker = UpdateChecker(
        client: client,
        currentVersion: () async => '1.0.0',
      );
      expect(await checker.checkForUpdate(), isNull);
    });

    test('DiskPhotoStore sanitizes extensions and HabitActions preserves shared photos', () async {
      final tmp = Directory.systemTemp.createTempSync('dt_adv_photo_');
      addTearDown(() => tmp.delete(recursive: true));
      final store = DiskPhotoStore(Directory(p.join(tmp.path, 'photos')));
      final weird = File(p.join(tmp.path, 'bad.tar.gz'))
        ..writeAsBytesSync([1, 2, 3]);
      final savedName = await store.savePicked(weird.path, id: 'p1');
      expect(savedName, 'p1.jpg');

      final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final h = await repo.addHabit(habit('ph', logType: LogType.photo));
      // Two entries share p1.jpg (e.g., from a restored backup).
      await repo.putEntry(
        Entry(
          habitId: h.id,
          day: mon,
          state: EntryState.done,
          photoPath: savedName,
          loggedAt: DateTime.utc(2026, 10, 5),
        ),
      );
      await repo.putEntry(
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
      final act = HabitActions(
        repo: repo,
        photos: store,
        now: () => DateTime.utc(2026, 10, 6),
        newId: () => 'p2',
      );
      await act.logPhoto(h, tue, replacement.path);
      expect(
        store.fileFor(savedName).existsSync(),
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
