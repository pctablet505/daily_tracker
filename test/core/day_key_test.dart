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

  group('range', () {
    const first = DayKey(1, 1, 1);
    const last = DayKey(9999, 12, 31);

    void roundTrips(DayKey d) =>
        expect(DayKey.tryParse(d.toString()), d, reason: d.toString());

    test('stepping past either end stops at 0001-01-01 or 9999-12-31', () {
      expect(first.addDays(-1), first);
      expect(first.addDays(-1000000), first);
      expect(const DayKey(2026, 10, 11).addDays(-1 << 40), first);
      expect(last.addDays(1), last);
      expect(const DayKey(2026, 10, 11).addDays(1 << 40), last);
      expect(first.monthStartPlus(-1), first);
      expect(last.monthStartPlus(1), last);
      expect(const DayKey(2026, 10, 11).monthStartPlus(1 << 40), last);
      expect(last.monthEnd, last);
      expect(const DayKey(9999, 12, 5).monthEnd, last);
      for (final d in [
        first.addDays(-1),
        last.addDays(1),
        first.monthStartPlus(-1),
        last.monthStartPlus(1),
      ]) {
        roundTrips(d);
      }
    });

    test('a day built from out-of-range parts is clamped into a real day', () {
      expect(const DayKey(0, 12, 31), first);
      expect(const DayKey(-5, 6, 6), first);
      expect(const DayKey(10000, 1, 1), last);
      expect(const DayKey(2026, 2, 30), const DayKey(2026, 2, 28));
      expect(const DayKey(2028, 2, 30), const DayKey(2028, 2, 29));
      expect(const DayKey(2026, 4, 31), const DayKey(2026, 4, 30));
      expect(const DayKey(2026, 13, 1), const DayKey(2026, 12, 1));
      expect(const DayKey(2026, 0, 0), const DayKey(2026, 1, 1));
      expect(DayKey.fromDate(DateTime.utc(-3, 4, 5)), first);
      expect(DayKey.fromDate(DateTime.utc(12000, 4, 5)), last);
      for (final d in const [
        DayKey(0, 12, 31),
        DayKey(10000, 1, 1),
        DayKey(2026, 2, 30),
        DayKey(1900, 2, 29),
        DayKey(2026, 13, 0),
      ]) {
        roundTrips(d);
      }
    });

    test('every day near both ends prints text that reads back as itself', () {
      for (var n = -3; n <= 400; n++) {
        roundTrips(first.addDays(n));
        roundTrips(last.addDays(-n));
      }
    });

    test('through ends at the last possible day', () {
      // take() keeps a range that never ends from hanging the test.
      expect(last.addDays(-2).through(last).take(5).toList(), [
        last.addDays(-2),
        last.addDays(-1),
        last,
      ]);
    });
  });
}
