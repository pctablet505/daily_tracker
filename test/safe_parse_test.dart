import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/core/utils/safe_parse.dart';

void main() {
  group('SafeParse.boolean', () {
    test('returns true for 1', () {
      expect(SafeParse.boolean(1), isTrue);
    });

    test('returns false for 0', () {
      expect(SafeParse.boolean(0), isFalse);
    });

    test('handles bool values', () {
      expect(SafeParse.boolean(true), isTrue);
      expect(SafeParse.boolean(false), isFalse);
    });

    test('handles string values', () {
      expect(SafeParse.boolean('1'), isTrue);
      expect(SafeParse.boolean('true'), isTrue);
      expect(SafeParse.boolean('yes'), isTrue);
      expect(SafeParse.boolean('0'), isFalse);
      expect(SafeParse.boolean('false'), isFalse);
    });

    test('returns default for null', () {
      expect(SafeParse.boolean(null), isFalse);
      expect(SafeParse.boolean(null, defaultValue: true), isTrue);
    });

    test('returns default for unsupported types', () {
      expect(SafeParse.boolean([]), isFalse);
    });
  });

  group('SafeParse.integer', () {
    test('returns int for int', () {
      expect(SafeParse.integer(42), equals(42));
    });

    test('returns int for double', () {
      expect(SafeParse.integer(42.9), equals(42));
    });

    test('parses string int', () {
      expect(SafeParse.integer('42'), equals(42));
    });

    test('returns default for null', () {
      expect(SafeParse.integer(null), equals(0));
      expect(SafeParse.integer(null, defaultValue: 7), equals(7));
    });

    test('returns default for invalid string', () {
      expect(SafeParse.integer('not-a-number'), equals(0));
    });
  });

  group('SafeParse.float', () {
    test('returns double for double', () {
      expect(SafeParse.float(3.14), closeTo(3.14, 0.001));
    });

    test('returns double for int', () {
      expect(SafeParse.float(42), closeTo(42.0, 0.001));
    });

    test('parses string double', () {
      expect(SafeParse.float('3.14'), closeTo(3.14, 0.001));
    });

    test('returns default for null', () {
      expect(SafeParse.float(null), equals(0.0));
    });

    test('returns default for invalid string', () {
      expect(SafeParse.float('not-a-number'), equals(0.0));
    });
  });

  group('SafeParse.string', () {
    test('returns string for string', () {
      expect(SafeParse.string('hello'), equals('hello'));
    });

    test('converts other types to string', () {
      expect(SafeParse.string(42), equals('42'));
    });

    test('returns default for null', () {
      expect(SafeParse.string(null), equals(''));
      expect(
          SafeParse.string(null, defaultValue: 'fallback'), equals('fallback'));
    });
  });

  group('SafeParse.stringNullable', () {
    test('returns null for null', () {
      expect(SafeParse.stringNullable(null), isNull);
    });

    test('returns string for string', () {
      expect(SafeParse.stringNullable('hello'), equals('hello'));
    });

    test('converts other types to string', () {
      expect(SafeParse.stringNullable(42), equals('42'));
    });
  });

  group('SafeParse.dateTime', () {
    test('parses ISO-8601 string', () {
      final result = SafeParse.dateTime('2024-06-15T10:30:00.000');
      expect(result, isNotNull);
      expect(result!.year, equals(2024));
      expect(result.month, equals(6));
      expect(result.day, equals(15));
    });

    test('returns null for null', () {
      expect(SafeParse.dateTime(null), isNull);
    });

    test('returns null for invalid string', () {
      expect(SafeParse.dateTime('not-a-date'), isNull);
    });

    test('returns DateTime for DateTime input', () {
      final now = DateTime.now();
      expect(SafeParse.dateTime(now), equals(now));
    });
  });

  group('SafeParse.dateTimeOrNow', () {
    test('parses valid string', () {
      final result = SafeParse.dateTimeOrNow('2024-06-15T10:30:00.000');
      expect(result.year, equals(2024));
    });

    test('returns now for null', () {
      final before = DateTime.now();
      final result = SafeParse.dateTimeOrNow(null);
      final after = DateTime.now();
      expect(result.isAfter(before) || result.isAtSameMomentAs(before), isTrue);
      expect(result.isBefore(after) || result.isAtSameMomentAs(after), isTrue);
    });

    test('returns default for invalid string', () {
      final fallback = DateTime(2020, 1, 1);
      final result = SafeParse.dateTimeOrNow('invalid', defaultValue: fallback);
      expect(result, equals(fallback));
    });
  });
}
