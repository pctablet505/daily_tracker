import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/lock.dart';
import 'providers.dart';

/// Set in `main`; tests replace it.
final lockServiceProvider = Provider<LockService>(
  (ref) => throw UnimplementedError('lockServiceProvider is not set'),
);

/// Whether the lock screen is showing.
class LockController extends Notifier<bool> {
  /// A camera, picker or share sheet takes the user out of the app on purpose, so
  /// the app stays open for at least this long after one, whatever "lock after" says.
  static const externalGraceSeconds = 300;

  DateTime? _pausedAt;
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
    _pausedAt ??= now;
    final ended = _externalEndedAt;
    _externalEndedAt = null;
    if (ended != null &&
        !now.isBefore(ended) &&
        now.difference(ended) <= const Duration(seconds: 5)) {
      _graceOnNextResume = true;
    }
  }

  /// The app came back; locks again if it was away long enough.
  void resumed() {
    final since = _pausedAt;
    _pausedAt = null;
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
    if (shouldLock(
      awayFor: away,
      lockAfterSeconds: onTrip && lockAfter < externalGraceSeconds
          ? externalGraceSeconds
          : lockAfter,
    ))
      state = true;
  }

  void lockNow() {
    if (_lockApplies) state = true;
  }

  void _markUnlocked() {
    _pausedAt = null;
    _graceOnNextResume = false;
    _externalEndedAt = null;
    state = false;
  }

  /// Runs something that takes the user out of the app on purpose (camera, file
  /// picker, share sheet). A short trip does not lock the app; a long one still does.
  Future<T> runExternal<T>(Future<T> Function() job) async {
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
      } else if (_externalDepth == 0 && !_resumedInExternal) {
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
