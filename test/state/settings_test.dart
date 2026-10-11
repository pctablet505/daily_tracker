import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> prefs([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  test('starts with the documented defaults', () async {
    final s = Settings.read(await prefs());
    expect(s.theme, ThemeChoice.system);
    expect(s.streakThreshold, 60);
    expect(s.remindersOn, isTrue);
    expect(
      (s.quietHoursOn, s.quietStartMinutes, s.quietEndMinutes),
      (false, 22 * 60, 7 * 60),
    );
    expect((s.eveningCheckInOn, s.eveningCheckInMinutes), (true, 21 * 60));
    expect((s.lockOn, s.lockBiometric, s.lockAfterSeconds), (false, true, 60));
    expect(s.onboardingDone, isFalse);
    expect((s.wifiOnlyBackup, s.wifiOnlyUpdate), (true, false));
  });

  test('what is written is read back', () async {
    final p = await prefs();
    const s = Settings(
      theme: ThemeChoice.dark,
      streakThreshold: 80,
      remindersOn: false,
      quietHoursOn: true,
      quietStartMinutes: 23 * 60 + 30,
      quietEndMinutes: 6 * 60,
      eveningCheckInOn: false,
      eveningCheckInMinutes: 20 * 60 + 15,
      lockOn: true,
      lockBiometric: false,
      lockAfterSeconds: 300,
      onboardingDone: true,
      wifiOnlyBackup: false,
      wifiOnlyUpdate: true,
    );
    await s.write(p);
    expect(Settings.read(p), s);
  });

  test('a stored value out of range falls back to something safe', () async {
    final s = Settings.read(
      await prefs({
        'streakThreshold': 500,
        'quietStartMinutes': -5,
        'quietEndMinutes': 99999,
        'eveningCheckInMinutes': 1440,
        'lockAfterSeconds': -1,
        'theme': 'neon',
      }),
    );
    expect(s.streakThreshold, 100);
    expect(s.quietStartMinutes, 22 * 60);
    expect(s.quietEndMinutes, 7 * 60);
    expect(s.eveningCheckInMinutes, 21 * 60);
    expect(s.lockAfterSeconds, 60);
    expect(s.theme, ThemeChoice.system);
  });

  test('a streak threshold below 1 is raised to 1', () async {
    expect(
      Settings.read(await prefs({'streakThreshold': 0})).streakThreshold,
      1,
    );
  });

  group('backup', () {
    test('exports only the preferences that make sense on another phone', () {
      final m = const Settings(
        lockOn: true,
        onboardingDone: true,
        theme: ThemeChoice.light,
      ).exportMap();
      expect(m.keys.toSet(), {
        'theme',
        'streakThreshold',
        'remindersOn',
        'quietHoursOn',
        'quietStartMinutes',
        'quietEndMinutes',
        'eveningCheckInOn',
        'eveningCheckInMinutes',
        'wifiOnlyBackup',
        'wifiOnlyUpdate',
      });
      expect(m['theme'], 'light');
    });

    test('importing replaces the exported ones and leaves the rest alone', () {
      const current = Settings(
        lockOn: true,
        lockAfterSeconds: 300,
        onboardingDone: true,
        streakThreshold: 60,
      );
      final s = current.withImported({
        'streakThreshold': 80,
        'theme': 'dark',
        'lockOn': false,
        'onboardingDone': false,
      });
      expect(s.streakThreshold, 80);
      expect(s.theme, ThemeChoice.dark);
      expect(
        (s.lockOn, s.lockAfterSeconds, s.onboardingDone),
        (true, 300, true),
      );
    });

    test('importing ignores values of the wrong type or out of range', () {
      const current = Settings(streakThreshold: 70, theme: ThemeChoice.dark);
      final s = current.withImported({
        'streakThreshold': 'high',
        'theme': 5,
        'quietStartMinutes': 5000,
        'remindersOn': 'yes',
      });
      expect(s, current);
    });
  });

  test('equal settings are equal, and any differing field breaks it', () {
    expect(const Settings(), const Settings());
    expect(const Settings().hashCode, const Settings().hashCode);
    expect(const Settings() == const Settings(streakThreshold: 61), isFalse);
    expect(const Settings() == const Settings(lockOn: true), isFalse);
  });

  test('copyWith changes one field', () {
    const s = Settings();
    expect(s.copyWith(streakThreshold: 40).streakThreshold, 40);
    expect(s.copyWith(streakThreshold: 40).theme, s.theme);
  });
}
