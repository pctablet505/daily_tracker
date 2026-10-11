import 'package:shared_preferences/shared_preferences.dart';

enum ThemeChoice { system, light, dark }

const _defaultQuietStart = 22 * 60;
const _defaultQuietEnd = 7 * 60;
const _defaultCheckIn = 21 * 60;
const _defaultLockAfter = 60;

/// User preferences. Stored one key per field in SharedPreferences.
final class Settings {
  const Settings({
    this.theme = ThemeChoice.system,
    this.streakThreshold = 60,
    this.remindersOn = true,
    this.quietHoursOn = false,
    this.quietStartMinutes = _defaultQuietStart,
    this.quietEndMinutes = _defaultQuietEnd,
    this.eveningCheckInOn = true,
    this.eveningCheckInMinutes = _defaultCheckIn,
    this.lockOn = false,
    this.lockBiometric = true,
    this.lockAfterSeconds = _defaultLockAfter,
    this.onboardingDone = false,
    this.wifiOnlyBackup = true,
    this.wifiOnlyUpdate = false,
  });

  final ThemeChoice theme;

  /// Share of the day's Do habits (percent) that keeps a streak going.
  final int streakThreshold;
  final bool remindersOn;
  final bool quietHoursOn;
  final int quietStartMinutes;
  final int quietEndMinutes;
  final bool eveningCheckInOn;
  final int eveningCheckInMinutes;
  final bool lockOn;
  final bool lockBiometric;

  /// How long the app may be out of sight before it locks again.
  final int lockAfterSeconds;
  final bool onboardingDone;
  final bool wifiOnlyBackup;
  final bool wifiOnlyUpdate;

  static const _exported = [
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
  ];

  static ThemeChoice _theme(Object? v) =>
      ThemeChoice.values.where((t) => t.name == v).firstOrNull ??
      ThemeChoice.system;

  static bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;
  static int _threshold(Object? v) => v is int ? v.clamp(1, 100) : 60;
  static int _minutes(Object? v, int fallback) =>
      v is int && v >= 0 && v < 1440 ? v : fallback;
  static int _lockAfter(Object? v) =>
      v is int && v >= 0 ? v : _defaultLockAfter;

  factory Settings.fromMap(Map<String, Object?> m) => Settings(
    theme: _theme(m['theme']),
    streakThreshold: _threshold(m['streakThreshold']),
    remindersOn: _bool(m['remindersOn'], true),
    quietHoursOn: _bool(m['quietHoursOn'], false),
    quietStartMinutes: _minutes(m['quietStartMinutes'], _defaultQuietStart),
    quietEndMinutes: _minutes(m['quietEndMinutes'], _defaultQuietEnd),
    eveningCheckInOn: _bool(m['eveningCheckInOn'], true),
    eveningCheckInMinutes: _minutes(
      m['eveningCheckInMinutes'],
      _defaultCheckIn,
    ),
    lockOn: _bool(m['lockOn'], false),
    lockBiometric: _bool(m['lockBiometric'], true),
    lockAfterSeconds: _lockAfter(m['lockAfterSeconds']),
    onboardingDone: _bool(m['onboardingDone'], false),
    wifiOnlyBackup: _bool(m['wifiOnlyBackup'], true),
    wifiOnlyUpdate: _bool(m['wifiOnlyUpdate'], false),
  );

  Map<String, Object> toMap() => {
    'theme': theme.name,
    'streakThreshold': streakThreshold,
    'remindersOn': remindersOn,
    'quietHoursOn': quietHoursOn,
    'quietStartMinutes': quietStartMinutes,
    'quietEndMinutes': quietEndMinutes,
    'eveningCheckInOn': eveningCheckInOn,
    'eveningCheckInMinutes': eveningCheckInMinutes,
    'lockOn': lockOn,
    'lockBiometric': lockBiometric,
    'lockAfterSeconds': lockAfterSeconds,
    'onboardingDone': onboardingDone,
    'wifiOnlyBackup': wifiOnlyBackup,
    'wifiOnlyUpdate': wifiOnlyUpdate,
  };

  /// Reads a stored value of the right type, or null (so a wrong-typed key
  /// from an old build does not throw).
  static Settings read(SharedPreferences p) {
    Object? get(String k) {
      try {
        return p.get(k);
      } catch (_) {
        return null;
      }
    }

    return Settings.fromMap({
      for (final k in const Settings().toMap().keys) k: get(k),
    });
  }

  Future<void> write(SharedPreferences p) async {
    for (final e in toMap().entries) {
      final v = e.value;
      if (v is bool) {
        await p.setBool(e.key, v);
      } else if (v is int) {
        await p.setInt(e.key, v);
      } else if (v is String) {
        await p.setString(e.key, v);
      }
    }
  }

  /// The preferences a backup carries. Lock, onboarding and account choices stay on the phone.
  Map<String, Object> exportMap() {
    final all = toMap();
    return {for (final k in _exported) k: all[k]!};
  }

  /// This settings object with the exported preferences replaced by [m]. A
  /// value of the wrong type or out of range is ignored and the current one kept.
  Settings withImported(Map<String, Object> m) {
    final current = toMap();
    final cleaned = Settings.fromMap({
      ...current,
      for (final k in _exported)
        if (m.containsKey(k)) k: m[k],
    }).toMap();
    return Settings.fromMap({
      ...current,
      for (final k in _exported)
        if (m[k] != null && cleaned[k] == m[k]) k: m[k],
    });
  }

  Settings copyWith({
    ThemeChoice? theme,
    int? streakThreshold,
    bool? remindersOn,
    bool? quietHoursOn,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? eveningCheckInOn,
    int? eveningCheckInMinutes,
    bool? lockOn,
    bool? lockBiometric,
    int? lockAfterSeconds,
    bool? onboardingDone,
    bool? wifiOnlyBackup,
    bool? wifiOnlyUpdate,
  }) => Settings(
    theme: theme ?? this.theme,
    streakThreshold: streakThreshold ?? this.streakThreshold,
    remindersOn: remindersOn ?? this.remindersOn,
    quietHoursOn: quietHoursOn ?? this.quietHoursOn,
    quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
    quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    eveningCheckInOn: eveningCheckInOn ?? this.eveningCheckInOn,
    eveningCheckInMinutes: eveningCheckInMinutes ?? this.eveningCheckInMinutes,
    lockOn: lockOn ?? this.lockOn,
    lockBiometric: lockBiometric ?? this.lockBiometric,
    lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    wifiOnlyBackup: wifiOnlyBackup ?? this.wifiOnlyBackup,
    wifiOnlyUpdate: wifiOnlyUpdate ?? this.wifiOnlyUpdate,
  );

  @override
  bool operator ==(Object other) =>
      other is Settings && _eq(other.toMap(), toMap());

  static bool _eq(Map<String, Object> a, Map<String, Object> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll(toMap().entries.map((e) => Object.hash(e.key, e.value)));
}
