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

  Future<void> markOffered(String version) async {
    final now = _now();
    await _markChecked(now);
    await _prefs.setString(_offeredVersionKey, version);
    await _prefs.setInt(_offeredAtKey, now.millisecondsSinceEpoch);
  }

  /// A release to show the user now, or null.
  Future<ReleaseInfo?> releaseToOffer({bool recordOffer = true}) async {
    final now = _now();
    final last = _time(_lastCheckKey);
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) < _checkEvery) {
      return null;
    }
    if (!await _isOnline()) return null;
    if (_wifiOnly() && !await _isOnWifi()) return null;

    final result = await _check();
    if (result is! UpdateAvailable) {
      // A failed check does not count as a check for long, so the next launch tries again soon.
      final stamp = result is UpdateCheckFailed
          ? now.subtract(_checkEvery - _retryAfterFailure)
          : now;
      await _markChecked(stamp);
      return null;
    }

    final release = result.release;
    final offeredAt = _time(_offeredAtKey);
    if (_prefs.getString(_skippedKey) == release.version ||
        (_prefs.getString(_offeredVersionKey) == release.version &&
            offeredAt != null &&
            !now.isBefore(offeredAt) &&
            now.difference(offeredAt) < _offerAgainAfter)) {
      await _markChecked(now);
      return null;
    }
    // Without [recordOffer] the check only counts once [markOffered] says the
    // user saw it: an offer given up (the app locked or left meanwhile) is
    // asked for again next time.
    if (recordOffer) await markOffered(release.version);
    return release;
  }

  Future<void> _markChecked(DateTime at) =>
      _prefs.setInt(_lastCheckKey, at.millisecondsSinceEpoch);
}
