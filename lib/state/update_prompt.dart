import 'package:shared_preferences/shared_preferences.dart';

import '../services/updater.dart';

/// Decides when the app should ask GitHub for a new release and when to show it:
/// not on every launch, not on mobile data when that is switched off, and not
/// again for the same version for a few days (or ever, if the user skips it).
class UpdatePrompter {
  UpdatePrompter({
    required this._prefs,
    required this._now,
    required this._check,
    required this._isOnWifi,
    required this._isOnline,
    required this._wifiOnly,
  });

  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final Future<UpdateCheck> Function() _check;
  final Future<bool> Function() _isOnWifi;
  final Future<bool> Function() _isOnline;
  final bool Function() _wifiOnly;

  static const _lastCheckKey = 'update.lastCheck';
  static const _checkEvery = Duration(hours: 12);
  static const _retryAfterFailure = Duration(hours: 1);
  static const _skippedKey = 'update.skipped';
  static const _offeredVersionKey = 'update.offeredVersion';
  static const _offeredAtKey = 'update.offeredAt';
  static const _offerAgainAfter = Duration(days: 3);

  DateTime? _time(String key) {
    final ms = _prefs.getInt(key);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> skip(String version) => _prefs.setString(_skippedKey, version);

  /// A release to show the user now, or null.
  Future<ReleaseInfo?> releaseToOffer() async {
    final now = _now();
    final last = _time(_lastCheckKey);
    if (last != null && now.difference(last) < _checkEvery) return null;
    if (!await _isOnline()) return null;
    if (_wifiOnly() && !await _isOnWifi()) return null;

    final result = await _check();
    // A failed check does not count as a check for long, so the next launch tries again soon.
    final stamp = result is UpdateCheckFailed
        ? now.subtract(_checkEvery - _retryAfterFailure)
        : now;
    await _prefs.setInt(_lastCheckKey, stamp.millisecondsSinceEpoch);
    if (result is! UpdateAvailable) return null;

    final release = result.release;
    if (_prefs.getString(_skippedKey) == release.version) return null;
    final offeredAt = _time(_offeredAtKey);
    if (_prefs.getString(_offeredVersionKey) == release.version &&
        offeredAt != null &&
        now.difference(offeredAt) < _offerAgainAfter) {
      return null;
    }
    await _prefs.setString(_offeredVersionKey, release.version);
    await _prefs.setInt(_offeredAtKey, now.millisecondsSinceEpoch);
    return release;
  }
}
