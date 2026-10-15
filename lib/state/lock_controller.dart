import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/lock.dart';
import 'providers.dart';

/// Set in `main`; tests replace it.
final lockServiceProvider = Provider<LockService>(
  (ref) => throw UnimplementedError('lockServiceProvider is not set'),
);

/// See [phoneLockIsCredentialOnly]. Tests replace it.
final phoneLockCredentialOnlyProvider = FutureProvider<bool>(
  (ref) => phoneLockIsCredentialOnly(),
);

/// Whether the phone's screen lock may open the app ("Forgot PIN? Use phone
/// lock"). Where the phone's prompt also takes a fingerprint (Android 10 and
/// older) it would get round fingerprint unlock being switched off.
final phoneLockAllowedProvider = FutureProvider<bool>(
  (ref) async =>
      ref.watch(settingsProvider.select((s) => s.lockBiometric)) ||
      await ref.watch(phoneLockCredentialOnlyProvider.future),
);

/// Whether the lock screen is showing.
class LockController extends Notifier<bool> {
  /// A camera, picker or share sheet takes the user out of the app on purpose, so
  /// the app stays open for at least this long after one, whatever "lock after" says.
  static const externalGraceSeconds = 300;

  DateTime? _pausedAt;
  Future<Duration?>? _pausedBoot;
  Future<void>? _bootCheck;
  int _externalDepth = 0;
  bool _resumedInExternal = false;
  DateTime? _externalEndedAt;

  /// An external job returned while the app was still in the background; the
  /// "resumed" that follows belongs to that trip.
  bool _graceOnNextResume = false;

  @override
  bool build() {
    final on = ref.read(settingsProvider).lockOn;
    return on && ref.read(lockServiceProvider).hasPin;
  }

  bool get _lockApplies =>
      ref.read(settingsProvider).lockOn && ref.read(lockServiceProvider).hasPin;

  /// The app went to the background.
  void paused() {
    final now = ref.read(clockProvider)();
    if (_pausedAt == null) {
      _pausedAt = now;
      _pausedBoot = ref.read(elapsedRealtimeProvider)();
    }
    final ended = _externalEndedAt;
    _externalEndedAt = null;
    if (ended != null &&
        !now.isBefore(ended) &&
        now.difference(ended) <= const Duration(seconds: 5)) {
      _graceOnNextResume = true;
    }
  }

  /// The app came back; locks again if it was away long enough by the wall
  /// clock, or by the time since boot, which setting the clock back cannot
  /// shrink. That second answer comes a moment later: see [settled].
  void resumed() {
    final since = _pausedAt;
    final sinceBoot = _pausedBoot;
    _pausedAt = null;
    _pausedBoot = null;
    _externalEndedAt = null;
    if (_externalDepth > 0) _resumedInExternal = true;
    final onTrip = _externalDepth > 0 || _graceOnNextResume;
    _graceOnNextResume = false;
    if (!_lockApplies) {
      state = false;
      return;
    }
    if (since == null) return;
    final away = ref.read(clockProvider)().difference(since);
    final lockAfter = ref.read(settingsProvider).lockAfterSeconds;
    final limit = onTrip && lockAfter < externalGraceSeconds
        ? externalGraceSeconds
        : lockAfter;
    if (shouldLock(awayFor: away, lockAfterSeconds: limit)) {
      state = true;
    } else if (sinceBoot != null) {
      _bootCheck = _lockIfLongSinceBoot(sinceBoot, limit);
    }
  }

  Future<void> _lockIfLongSinceBoot(
    Future<Duration?> sinceBoot,
    int limit,
  ) async {
    final before = await sinceBoot;
    final after = await ref.read(elapsedRealtimeProvider)();
    if (before == null || after == null || !ref.mounted) return;
    if (_lockApplies &&
        shouldLock(awayFor: after - before, lockAfterSeconds: limit)) {
      state = true;
    }
  }

  /// Completes once the last [resumed] has its answer from the time since boot.
  Future<void> get settled => _bootCheck ?? Future.value();

  void lockNow() {
    if (_lockApplies) state = true;
  }

  void _markUnlocked() {
    _pausedAt = null;
    _pausedBoot = null;
    _graceOnNextResume = false;
    _externalEndedAt = null;
    state = false;
  }

  /// Runs something that takes the user out of the app on purpose (camera, file
  /// picker, share sheet). A short trip does not lock the app; a long one still does.
  /// [opensActivity] is for a job that only starts another screen and returns
  /// before Android pauses this one (a link, the settings page, the installer).
  Future<T> runExternal<T>(
    Future<T> Function() job, {
    bool opensActivity = false,
  }) async {
    if (_externalDepth == 0) _resumedInExternal = false;
    _externalDepth++;
    try {
      return await job();
    } finally {
      _externalDepth--;
      // The result can arrive before the app is told it is back, or before the
      // activity pauses when launching an external intent.
      if (_pausedAt != null) {
        _graceOnNextResume = true;
      } else if (opensActivity && _externalDepth == 0 && !_resumedInExternal) {
        _externalEndedAt = ref.read(clockProvider)();
      }
    }
  }

  Future<PinCheck> unlockWithPin(String pin) async {
    final r = await ref.read(lockServiceProvider).checkPin(pin);
    if (r.ok) _markUnlocked();
    return r;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!ref.read(settingsProvider).lockBiometric) return false;
    final ok = await runExternal(
      () => ref.read(lockServiceProvider).unlockWithBiometrics(),
    );
    if (ok) _markUnlocked();
    return ok;
  }

  Future<bool> unlockWithDeviceCredential() async {
    if (!await ref.read(phoneLockAllowedProvider.future)) return false;
    final ok = await runExternal(
      () => ref.read(lockServiceProvider).unlockWithDeviceCredential(),
    );
    if (ok) _markUnlocked();
    return ok;
  }
}

final lockedProvider = NotifierProvider<LockController, bool>(
  LockController.new,
);
