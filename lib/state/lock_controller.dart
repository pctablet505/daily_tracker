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
  bool _external = false;

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
  void paused() => _pausedAt = ref.read(clockProvider)();

  /// The app came back; locks again if it was away long enough.
  void resumed() {
    final since = _pausedAt;
    _pausedAt = null;
    final onTrip = _external || _graceOnNextResume;
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

  /// Runs something that takes the user out of the app on purpose (camera, file
  /// picker, share sheet). A short trip does not lock the app; a long one still does.
  Future<T> runExternal<T>(Future<T> Function() job) async {
    _external = true;
    try {
      return await job();
    } finally {
      _external = false;
      // The result can arrive before the app is told it is back.
      if (_pausedAt != null) _graceOnNextResume = true;
    }
  }

  Future<PinCheck> unlockWithPin(String pin) async {
    final r = await ref.read(lockServiceProvider).checkPin(pin);
    if (r.ok) state = false;
    return r;
  }

  Future<bool> unlockWithBiometrics() async {
    final ok = await runExternal(
      () => ref.read(lockServiceProvider).unlockWithBiometrics(),
    );
    if (ok) state = false;
    return ok;
  }

  Future<bool> unlockWithDeviceCredential() async {
    final ok = await runExternal(
      () => ref.read(lockServiceProvider).unlockWithDeviceCredential(),
    );
    if (ok) state = false;
    return ok;
  }
}

final lockedProvider = NotifierProvider<LockController, bool>(
  LockController.new,
);
