import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/core/utils/crypto_utils.dart';

void main() {
  group('CryptoUtils Tests', () {
    test('hashPin produces consistent results for same input', () {
      final hash1 = CryptoUtils.hashPin('1234');
      final hash2 = CryptoUtils.hashPin('1234');
      expect(hash1, equals(hash2));
    });

    test('hashPin produces different results for different inputs', () {
      final hash1 = CryptoUtils.hashPin('1234');
      final hash2 = CryptoUtils.hashPin('5678');
      expect(hash1, isNot(equals(hash2)));
    });

    test('verifyPin returns true for correct PIN', () {
      final pin = '9876';
      final hash = CryptoUtils.hashPin(pin);
      expect(CryptoUtils.verifyPin(pin, hash), isTrue);
    });

    test('verifyPin returns false for incorrect PIN', () {
      final hash = CryptoUtils.hashPin('9876');
      expect(CryptoUtils.verifyPin('1234', hash), isFalse);
    });

    test('hashPin output is 64 characters (SHA-256 hex)', () {
      final hash = CryptoUtils.hashPin('0000');
      expect(hash.length, equals(64));
    });
  });
}
