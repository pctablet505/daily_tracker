import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  static const String _salt = 'DailyTracker2024!#';

  static String hashPin(String pin) {
    final bytes = utf8.encode(pin + _salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static bool verifyPin(String pin, String hash) {
    return hashPin(pin) == hash;
  }
}
