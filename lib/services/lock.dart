import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iterations = 20000;

/// PBKDF2 with HMAC-SHA-256; returns [length] bytes as hex.
String pbkdf2Sha256(String password, String salt, int iterations, int length) {
  final hmac = Hmac(sha256, utf8.encode(password));
  final saltBytes = utf8.encode(salt);
  final out = <int>[];
  var block = 1;
  while (out.length < length) {
    var u = hmac.convert([
      ...saltBytes,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
    block++;
  }
  return out
      .take(length)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

String hashPin(String pin, String salt) =>
    pbkdf2Sha256(pin, salt, _iterations, 32);

String newSalt() {
  final r = Random.secure();
  return base64Url.encode(
    Uint8List.fromList([for (var i = 0; i < 18; i++) r.nextInt(256)]),
  );
}

/// How long to wait after [failures] wrong PINs in a row.
Duration backoffFor(int failures) => switch (failures) {
  < 5 => Duration.zero,
  5 => const Duration(seconds: 30),
  6 => const Duration(minutes: 1),
  7 => const Duration(minutes: 5),
  8 => const Duration(minutes: 15),
  _ => const Duration(hours: 1),
};

/// Whether the app should ask for the PIN again after being out of sight for [awayFor].
bool shouldLock({required Duration awayFor, required int lockAfterSeconds}) =>
    awayFor.isNegative || awayFor >= Duration(seconds: lockAfterSeconds);

abstract interface class Biometrics {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason, {required bool biometricOnly});
}

final class LocalAuthBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(
    String reason, {
    required bool biometricOnly,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Local authentication failed: $e');
      return false;
    }
  }
}

final class PinCheck {
  const PinCheck({
    required this.ok,
    this.failures = 0,
    this.waitFor = Duration.zero,
  });
  final bool ok;
  final int failures;

  /// When non-zero the guess was not even checked: too many wrong ones.
  final Duration waitFor;
}

/// The PIN, its wrong-guess counter, and fingerprint / phone-lock unlocking.
class LockService {
  LockService({
    required this._prefs,
    required Biometrics biometrics,
    required this._now,
  }) : _bio = biometrics;

  final SharedPreferences _prefs;
  final Biometrics _bio;
  final DateTime Function() _now;

  static const _saltKey = 'lock.salt';
  static const _hashKey = 'lock.hash';
  static const _failKey = 'lock.failures';
  static const _untilKey = 'lock.until';

  bool get hasPin => _prefs.getString(_hashKey) != null;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin))
      throw ArgumentError.value(pin, 'pin', 'A PIN is 4 to 6 digits');
    final salt = newSalt();
    await _prefs.setString(_saltKey, salt);
    await _prefs.setString(_hashKey, hashPin(pin, salt));
    await _resetFailures();
  }

  Future<void> clearPin() async {
    await _prefs.remove(_saltKey);
    await _prefs.remove(_hashKey);
    await _resetFailures();
  }

  Future<void> _resetFailures() async {
    await _prefs.remove(_failKey);
    await _prefs.remove(_untilKey);
  }

  Future<PinCheck> checkPin(String pin) async {
    final until = _prefs.getInt(_untilKey);
    final now = _now().millisecondsSinceEpoch;
    if (until != null && now < until) {
      return PinCheck(
        ok: false,
        failures: _prefs.getInt(_failKey) ?? 0,
        waitFor: Duration(milliseconds: until - now),
      );
    }
    final salt = _prefs.getString(_saltKey);
    final hash = _prefs.getString(_hashKey);
    if (salt != null && hash != null && hashPin(pin, salt) == hash) {
      await _resetFailures();
      return const PinCheck(ok: true);
    }
    final failures = (_prefs.getInt(_failKey) ?? 0) + 1;
    await _prefs.setInt(_failKey, failures);
    final wait = backoffFor(failures);
    if (wait > Duration.zero)
      await _prefs.setInt(_untilKey, now + wait.inMilliseconds);
    return PinCheck(ok: false, failures: failures);
  }

  Future<bool> get biometricsAvailable => _bio.isAvailable();

  Future<bool> unlockWithBiometrics() async {
    if (!await _bio.isAvailable()) return false;
    return _bio.authenticate('Unlock Daily Tracker', biometricOnly: true);
  }

  /// The phone's own screen lock (PIN, pattern or password): the way back in after forgetting the app PIN.
  Future<bool> unlockWithDeviceCredential() => _bio.authenticate(
    'Unlock Daily Tracker with your phone lock',
    biometricOnly: false,
  );
}
