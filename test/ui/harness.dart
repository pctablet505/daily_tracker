import 'dart:async';
import 'dart:io';

import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/services/lock.dart';
import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/state/lock_controller.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../data/fixtures.dart';

final class NoNotifications implements ReminderScheduler {
  @override
  Future<void> init() async {}
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> replaceAll(
    List<PlannedReminder> plan, {
    bool Function(String? payload)? keepSnooze,
  }) async {}
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> launchPayload() async => null;
}

final class NoPhotos implements PhotoStore {
  @override
  Future<String> importFile(String sourcePath) async => 'x.jpg';
  @override
  File fileFor(String name) {
    // Like the real store: a name that could leave the photo folder is an error.
    if (name.isEmpty || name.startsWith('.') || name.contains('/')) {
      throw ArgumentError.value(name, 'name', 'not a file name');
    }
    return File('/definitely/not/here/$name');
  }

  @override
  Future<void> delete(String name) async {}
}

/// The screens under test never reach the database: ledgers are overridden.
final class _UnusedDatabase extends Fake implements Database {}

final class _NoBiometrics implements Biometrics {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> authenticate(
    String reason, {
    required bool biometricOnly,
  }) async => false;
}

/// Tests draw every letter as a wide square unless the real font is loaded, which
/// would report overflows that never happen on a phone. Call from setUpAll.
Future<void> loadAppFont() async {
  final loader = FontLoader('PlusJakartaSans')
    ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  await loader.load();
}

/// A realistic week of data: one of each kind of habit, some done, some not.
Ledger sampleLedger() {
  final habits = [
    habit('water', logType: LogType.number, goal: 8).copyWith(
      name: 'Drink water',
      unit: () => 'glasses',
      dayPart: DayPart.morning,
      area: () => 'Health',
    ),
    habit('run').copyWith(
      name: 'Go for a run',
      area: () => 'Health',
      reminderMinutes: () => 7 * 60 + 30,
    ),
    habit('read', mask: Habit.weekdaysOnly).copyWith(
      name: 'Read for twenty minutes before bed',
      area: () => 'Mind',
      dayPart: DayPart.evening,
    ),
    habit('weight', logType: LogType.number).copyWith(
      name: 'Weigh yourself',
      unit: () => 'kg',
      dayPart: DayPart.morning,
    ),
    habit(
      'journal',
      logType: LogType.note,
    ).copyWith(name: 'Journal', dayPart: DayPart.evening),
    habit('photo', logType: LogType.photo).copyWith(name: 'Progress photo'),
    stayClear('sugar').copyWith(name: 'No added sugar', area: () => 'Health'),
    stayClear('scroll').copyWith(name: 'No social media scrolling'),
    habit('old', end: wed).copyWith(name: 'Old habit that was archived'),
  ];
  final entries = <Entry>[
    for (final d in [mon, tue, wed, thu, fri, sat]) entry('run', d),
    entry('water', sun, EntryState.partial, 3),
    entry('weight', sat, EntryState.done, 75.9),
    entry('weight', fri, EntryState.done, 76.2),
    entry('weight', thu, EntryState.done, 76.6),
    slip('sugar', wed),
    Entry(
      habitId: 'photo',
      day: sat,
      state: EntryState.done,
      photoPath: 'p1.jpg',
      loggedAt: DateTime.utc(2026, 10, 10),
    ),
    Entry(
      habitId: 'journal',
      day: fri,
      state: EntryState.done,
      note: 'A good day',
      loggedAt: DateTime.utc(2026, 10, 9),
    ),
  ];
  return Ledger(
    habits: habits,
    entries: entries,
    seenDays: [mon, tue, wed, thu, fri, sat, sun],
  );
}

Future<List<Override>> baseOverrides({
  Ledger? ledger,
  DateTime? now,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({'onboardingDone': true, ...prefs});
  final sp = await SharedPreferences.getInstance();
  return [
    databaseProvider.overrideWithValue(_UnusedDatabase()),
    sharedPrefsProvider.overrideWithValue(sp),
    clockProvider.overrideWithValue(() => now ?? DateTime(2026, 10, 11, 9)),
    reminderSchedulerProvider.overrideWithValue(NoNotifications()),
    photoStoreProvider.overrideWithValue(NoPhotos()),
    lockServiceProvider.overrideWithValue(
      LockService(
        prefs: sp,
        biometrics: _NoBiometrics(),
        now: () => DateTime(2026, 10, 11, 9),
      ),
    ),
    appVersionProvider.overrideWith((ref) async => '2.0.0'),
    if (ledger != null) ledgerProvider.overrideWith((ref) async => ledger),
  ];
}

/// Runs [body] and returns every framework error it reported (overflows,
/// failed assertions) as a full report, so a failing render test says which
/// widget and where.
Future<List<String>> collectFrameworkErrors(
  Future<void> Function() body,
) async {
  final reports = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) =>
      reports.add(details.toDiagnosticsNode().toStringDeep());
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reports;
}

/// Pumps [home] in a phone-sized window with the app theme.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget home, {
  required List<Override> overrides,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Size size = const Size(360, 780),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  // Let futures from providers resolve, then settle animations.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
