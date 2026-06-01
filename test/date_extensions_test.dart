import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/core/extensions/date_extensions.dart';

void main() {
  group('DateTimeExtensions Tests', () {
    test('dateOnly strips time components', () {
      final date = DateTime(2024, 6, 15, 14, 30, 45);
      final result = date.dateOnly;
      expect(result.year, 2024);
      expect(result.month, 6);
      expect(result.day, 15);
      expect(result.hour, 0);
      expect(result.minute, 0);
      expect(result.second, 0);
    });

    test('isToday returns true for current date', () {
      final today = DateTime.now();
      expect(today.isToday, isTrue);
    });

    test('isToday returns false for yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(yesterday.isToday, isFalse);
    });

    test('isSameDay returns true for same day', () {
      final date1 = DateTime(2024, 6, 15, 10, 0);
      final date2 = DateTime(2024, 6, 15, 22, 30);
      expect(date1.isSameDay(date2), isTrue);
    });

    test('isSameDay returns false for different days', () {
      final date1 = DateTime(2024, 6, 15);
      final date2 = DateTime(2024, 6, 16);
      expect(date1.isSameDay(date2), isFalse);
    });

    test('formattedDate produces expected output', () {
      final date = DateTime(2024, 6, 15);
      expect(date.formattedDate, '15 Jun 2024');
    });

    test('formattedTime produces 12-hour format with AM', () {
      final date = DateTime(2024, 6, 15, 9, 5);
      expect(date.formattedTime, '9:05 AM');
    });

    test('formattedTime produces 12-hour format with PM', () {
      final date = DateTime(2024, 6, 15, 14, 30);
      expect(date.formattedTime, '2:30 PM');
    });

    test('formattedTime handles midnight', () {
      final date = DateTime(2024, 6, 15, 0, 0);
      expect(date.formattedTime, '12:00 AM');
    });

    test('formattedTime handles noon', () {
      final date = DateTime(2024, 6, 15, 12, 0);
      expect(date.formattedTime, '12:00 PM');
    });
  });
}
