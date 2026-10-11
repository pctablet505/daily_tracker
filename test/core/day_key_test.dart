import 'package:daily_tracker/core/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse', () {
    test('round-trips YYYY-MM-DD', () {
      expect(DayKey.parse('2026-10-11'), const DayKey(2026, 10, 11));
      expect(const DayKey(2026, 1, 5).toString(), '2026-01-05');
      expect(const DayKey(987, 3, 9).toString(), '0987-03-09');
    });

    test('accepts a leap day only in a leap year', () {
      expect(DayKey.tryParse('2028-02-29'), const DayKey(2028, 2, 29));
      expect(DayKey.tryParse('2026-02-29'), isNull);
      expect(DayKey.tryParse('1900-02-29'), isNull);
      expect(DayKey.tryParse('2000-02-29'), const DayKey(2000, 2, 29));
    });

    for (final bad in [
      '',
      '2026-1-1',
      '2026-13-01',
      '2026-00-10',
      '2026-02-30',
      '2026-04-31',
      '2026-10-32',
      '2026-10-00',
      ' 2026-10-11',
      '2026-10-11 ',
      '2026-10-11T00:00:00',
      '20261011',
      'abcd-ef-gh',
    ]) {
      test('rejects "$bad"', () {
        expect(DayKey.tryParse(bad), isNull);
        expect(() => DayKey.parse(bad), throwsFormatException);
      });
    }
  });

  group('addDays', () {
    test('crosses month and year ends', () {
      expect(const DayKey(2026, 1, 31).addDays(1), const DayKey(2026, 2, 1));
      expect(const DayKey(2026, 12, 31).addDays(1), const DayKey(2027, 1, 1));
      expect(const DayKey(2027, 1, 1).addDays(-1), const DayKey(2026, 12, 31));
      expect(const DayKey(2028, 2, 28).addDays(1), const DayKey(2028, 2, 29));
      expect(const DayKey(2026, 2, 28).addDays(1), const DayKey(2026, 3, 1));
    });

    test('zero is the same day; large steps work both ways', () {
      const d = DayKey(2026, 10, 11);
      expect(d.addDays(0), d);
      expect(d.addDays(365), const DayKey(2027, 10, 11));
      expect(d.addDays(-365), const DayKey(2025, 10, 11));
    });

    test('is not shifted by a daylight-saving change', () {
      // 2026-03-08 and 2026-11-01 are US clock-change days; calendar maths must not care.
      expect(const DayKey(2026, 3, 7).addDays(1), const DayKey(2026, 3, 8));
      expect(const DayKey(2026, 3, 8).addDays(1), const DayKey(2026, 3, 9));
      expect(const DayKey(2026, 10, 31).addDays(2), const DayKey(2026, 11, 2));
      expect(const DayKey(2026, 3, 29).addDays(1), const DayKey(2026, 3, 30));
    });
  });

  group('daysUntil', () {
    test('counts whole calendar days, signed', () {
      const a = DayKey(2026, 10, 11);
      expect(a.daysUntil(a), 0);
      expect(a.daysUntil(a.addDays(7)), 7);
      expect(a.addDays(7).daysUntil(a), -7);
      expect(const DayKey(2026, 12, 31).daysUntil(const DayKey(2027, 1, 1)), 1);
      expect(const DayKey(2026, 1, 1).daysUntil(const DayKey(2027, 1, 1)), 365);
      expect(const DayKey(2028, 1, 1).daysUntil(const DayKey(2029, 1, 1)), 366);
    });

    test('is exact across both daylight-saving changes of a year', () {
      expect(const DayKey(2026, 3, 1).daysUntil(const DayKey(2026, 4, 1)), 31);
      expect(
        const DayKey(2026, 10, 1).daysUntil(const DayKey(2026, 11, 30)),
        60,
      );
    });
  });

  group('through', () {
    test('includes both ends', () {
      final days = const DayKey(
        2026,
        2,
        27,
      ).through(const DayKey(2026, 3, 2)).toList();
      expect(days, [
        const DayKey(2026, 2, 27),
        const DayKey(2026, 2, 28),
        const DayKey(2026, 3, 1),
        const DayKey(2026, 3, 2),
      ]);
    });

    test('a single day yields itself; a reversed range is empty', () {
      const d = DayKey(2026, 10, 11);
      expect(d.through(d).toList(), [d]);
      expect(d.through(d.addDays(-1)), isEmpty);
    });
  });

  group('months', () {
    test('monthStartPlus moves by whole months and lands on the 1st', () {
      const d = DayKey(2026, 10, 17);
      expect(d.monthStartPlus(0), const DayKey(2026, 10, 1));
      expect(d.monthStartPlus(1), const DayKey(2026, 11, 1));
      expect(d.monthStartPlus(3), const DayKey(2027, 1, 1));
      expect(d.monthStartPlus(-1), const DayKey(2026, 9, 1));
      expect(d.monthStartPlus(-10), const DayKey(2025, 12, 1));
      expect(d.monthStartPlus(25), const DayKey(2028, 11, 1));
      expect(
        const DayKey(2026, 1, 31).monthStartPlus(-1),
        const DayKey(2025, 12, 1),
      );
    });

    test('monthEnd is the last day, including leap February', () {
      expect(const DayKey(2026, 10, 3).monthEnd, const DayKey(2026, 10, 31));
      expect(const DayKey(2026, 12, 1).monthEnd, const DayKey(2026, 12, 31));
      expect(const DayKey(2026, 2, 9).monthEnd, const DayKey(2026, 2, 28));
      expect(const DayKey(2028, 2, 9).monthEnd, const DayKey(2028, 2, 29));
      expect(const DayKey(2026, 4, 30).monthEnd, const DayKey(2026, 4, 30));
    });
  });

  group('weekday', () {
    test('matches DateTime (1 = Monday ... 7 = Sunday)', () {
      expect(const DayKey(2026, 10, 11).weekday, DateTime.sunday);
      expect(const DayKey(2026, 10, 12).weekday, DateTime.monday);
      expect(const DayKey(2026, 10, 17).weekday, DateTime.saturday);
    });
  });

  group('ordering and identity', () {
    test('compares by year, then month, then day', () {
      const a = DayKey(2026, 10, 11);
      expect(a < a.addDays(1), isTrue);
      expect(a <= a, isTrue);
      expect(a > a.addDays(-1), isTrue);
      expect(a >= a, isTrue);
      expect(const DayKey(2025, 12, 31) < const DayKey(2026, 1, 1), isTrue);
      expect(const DayKey(2026, 1, 31) < const DayKey(2026, 2, 1), isTrue);
      expect(const DayKey(2026, 2, 1) < const DayKey(2026, 1, 31), isFalse);
    });

    test('equal days share a hash and sort stably', () {
      expect(
        const DayKey(2026, 10, 11).hashCode,
        DayKey.parse('2026-10-11').hashCode,
      );
      final days = [
        const DayKey(2026, 10, 12),
        const DayKey(2026, 10, 10),
        const DayKey(2026, 10, 11),
      ]..sort();
      expect(days.map((d) => d.day), [10, 11, 12]);
    });

    test('fromDate keeps the local calendar day and drops the time', () {
      expect(
        DayKey.fromDate(DateTime(2026, 10, 11, 23, 59, 59)),
        const DayKey(2026, 10, 11),
      );
      expect(
        DayKey.fromDate(DateTime(2026, 10, 12, 0, 0, 1)),
        const DayKey(2026, 10, 12),
      );
      expect(const DayKey(2026, 10, 11).date, DateTime(2026, 10, 11));
    });
  });
}
