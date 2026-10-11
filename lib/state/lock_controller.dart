import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/lock.dart';
import 'providers.dart';

/// Set in `main`; tests replace it.
final lockServiceProvider = Provider<LockService>(
  (ref) => throw UnimplementedError('lockServiceProvider is not set'),
);

/// Whether the lock screen is showing.
class LockController extends Notifier<bool> {
  DateTime? _pausedAt;
  bool _external = false;

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
    if (_external) return;
    final since = _pausedAt;
    _pausedAt = null;
    if (!_lockApplies) {
      state = false;
      return;
    }
    if (since == null) return;
    final away = ref.read(clockProvider)().difference(since);
    if (shouldLock(
      awayFor: away,
      lockAfterSeconds: ref.read(settingsProvider).lockAfterSeconds,
    ))
      state = true;
  }

  void lockNow() {
    if (_lockApplies) state = true;
  }

  /// Runs something that takes the user out of the app on purpose (camera, file
  /// picker, share sheet) without it counting as leaving.
  Future<T> runExternal<T>(Future<T> Function() job) async {
    _external = true;
    try {
      return await job();
    } finally {
      _external = false;
      _pausedAt = null;
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
