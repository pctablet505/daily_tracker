import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  static const String _salt = 'DailyTracker2024!#';

  static String hashPin(String pin) {
    final bytes = utf8.encode(pin + _salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Constant-time string comparison to prevent timing attacks.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static bool verifyPin(String pin, String hash) {
    return _constantTimeEquals(hashPin(pin), hash);
  }
}
