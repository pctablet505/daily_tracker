import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/dependency_injection.dart';
import '../../services/sync/sync_service.dart';

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

final authStatusProvider = FutureProvider<bool>((ref) async {
  return getIt<SyncService>().isSignedIn();
});

class SettingsState {
  final bool notificationsEnabled;
  final bool autoSync;
  final bool wifiOnlyUpdates;
  final bool wifiOnlySync;
  final bool appLockEnabled;
  final bool biometricEnabled;
  final DateTime? quietHoursStart;
  final DateTime? quietHoursEnd;

  const SettingsState({
    this.notificationsEnabled = true,
    this.autoSync = true,
    this.wifiOnlyUpdates = true,
    this.wifiOnlySync = true,
    this.appLockEnabled = false,
    this.biometricEnabled = false,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  SettingsState copyWith({
    bool? notificationsEnabled,
    bool? autoSync,
    bool? wifiOnlyUpdates,
    bool? wifiOnlySync,
    bool? appLockEnabled,
    bool? biometricEnabled,
    DateTime? quietHoursStart,
    DateTime? quietHoursEnd,
  }) {
    return SettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      autoSync: autoSync ?? this.autoSync,
      wifiOnlyUpdates: wifiOnlyUpdates ?? this.wifiOnlyUpdates,
      wifiOnlySync: wifiOnlySync ?? this.wifiOnlySync,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      notificationsEnabled:
          prefs.getBool(AppConstants.prefNotificationsEnabled) ?? true,
      autoSync: prefs.getBool(AppConstants.prefAutoSync) ?? true,
      wifiOnlyUpdates: prefs.getBool(AppConstants.prefWifiOnlyUpdates) ?? true,
      wifiOnlySync: prefs.getBool(AppConstants.prefWifiOnlySync) ?? true,
      appLockEnabled: prefs.getBool(AppConstants.prefAppLockEnabled) ?? false,
      biometricEnabled:
          prefs.getBool(AppConstants.prefBiometricEnabled) ?? false,
      quietHoursStart:
          _parseTime(prefs.getString(AppConstants.prefQuietHoursStart)),
      quietHoursEnd:
          _parseTime(prefs.getString(AppConstants.prefQuietHoursEnd)),
    );
  }

  DateTime? _parseTime(String? timeStr) {
    if (timeStr == null) return null;
    try {
      final parts = timeStr.split(':');
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, int.parse(parts[0]),
          int.parse(parts[1]));
    } catch (_) {
      return null;
    }
  }

  String? _timeToString(DateTime? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefNotificationsEnabled, value);
    state = state.copyWith(notificationsEnabled: value);
  }

  Future<void> setAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefAutoSync, value);
    state = state.copyWith(autoSync: value);
  }

  Future<void> setWifiOnlyUpdates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefWifiOnlyUpdates, value);
    state = state.copyWith(wifiOnlyUpdates: value);
  }

  Future<void> setWifiOnlySync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefWifiOnlySync, value);
    state = state.copyWith(wifiOnlySync: value);
  }

  Future<void> setAppLockEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefAppLockEnabled, value);
    state = state.copyWith(appLockEnabled: value);
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefBiometricEnabled, value);
    state = state.copyWith(biometricEnabled: value);
  }

  Future<void> setQuietHours(DateTime? start, DateTime? end) async {
    final prefs = await SharedPreferences.getInstance();
    if (start != null) {
      await prefs.setString(
          AppConstants.prefQuietHoursStart, _timeToString(start)!);
    } else {
      await prefs.remove(AppConstants.prefQuietHoursStart);
    }
    if (end != null) {
      await prefs.setString(
          AppConstants.prefQuietHoursEnd, _timeToString(end)!);
    } else {
      await prefs.remove(AppConstants.prefQuietHoursEnd);
    }
    state = state.copyWith(quietHoursStart: start, quietHoursEnd: end);
  }
}
