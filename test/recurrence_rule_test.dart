import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/domain/entities/recurrence_rule.dart';

void main() {
  group('RecurrenceRule', () {
    group('encode/decode', () {
      test('round-trips daily', () {
        const rule = RecurrenceRule.daily();
        expect(rule.encode(), 'daily');
        expect(RecurrenceRule.decode('daily'), rule);
      });

      test('round-trips weekly', () {
        final rule = RecurrenceRule.weekly(const {1, 3, 5});
        expect(rule.encode(), 'weekly:1,3,5');
        expect(RecurrenceRule.decode('weekly:1,3,5'), rule);
      });

      test('round-trips timesPerWeek', () {
        final rule = RecurrenceRule.timesPerWeek(3);
        expect(rule.encode(), 'timesPerWeek:3');
        expect(RecurrenceRule.decode('timesPerWeek:3'), rule);
      });

      test('round-trips everyNDays', () {
        final rule = RecurrenceRule.everyNDays(2);
        expect(rule.encode(), 'everyNDays:2');
        expect(RecurrenceRule.decode('everyNDays:2'), rule);
      });

      test('legacy plain daily decodes to daily', () {
        expect(
          RecurrenceRule.decode('daily'),
          const RecurrenceRule.daily(),
        );
      });

      test('null decodes to none', () {
        expect(RecurrenceRule.decode(null), const RecurrenceRule.none());
      });

      test('empty decodes to none', () {
        expect(RecurrenceRule.decode(''), const RecurrenceRule.none());
      });

      test('malformed inputs fall back to none', () {
        expect(RecurrenceRule.decode('garbage'), const RecurrenceRule.none());
        expect(
          RecurrenceRule.decode('weekly:'),
          const RecurrenceRule.none(),
        );
        expect(
          RecurrenceRule.decode('weekly:0,8'),
          const RecurrenceRule.none(),
        );
        expect(
          RecurrenceRule.decode('timesPerWeek:0'),
          const RecurrenceRule.none(),
        );
        expect(
          RecurrenceRule.decode('timesPerWeek:9'),
          const RecurrenceRule.none(),
        );
        expect(
          RecurrenceRule.decode('everyNDays:0'),
          const RecurrenceRule.none(),
        );
      });
    });

    group('occursOn', () {
      test('daily is always true', () {
        const rule = RecurrenceRule.daily();
        final anchor = DateTime(2024, 6, 1);
        for (int i = 0; i < 10; i++) {
          expect(
            rule.occursOn(anchor.add(Duration(days: i)), anchor: anchor),
            isTrue,
          );
        }
      });

      test('none is always true (non-recurring shows every day)', () {
        const rule = RecurrenceRule.none();
        final anchor = DateTime(2024, 6, 1);
        expect(rule.occursOn(anchor, anchor: anchor), isTrue);
        expect(
          rule.occursOn(anchor.add(const Duration(days: 5)), anchor: anchor),
          isTrue,
        );
      });

      test('weekly matches only selected weekdays', () {
        final rule = RecurrenceRule.weekly(const {1, 3, 5}); // Mon, Wed, Fri
        final anchor = DateTime(2024, 6, 3); // Monday

        // 2024-06-03 is Monday.
        expect(rule.occursOn(DateTime(2024, 6, 3), anchor: anchor), isTrue);
        expect(rule.occursOn(DateTime(2024, 6, 4), anchor: anchor), isFalse);
        expect(rule.occursOn(DateTime(2024, 6, 5), anchor: anchor), isTrue);
        expect(rule.occursOn(DateTime(2024, 6, 6), anchor: anchor), isFalse);
        expect(rule.occursOn(DateTime(2024, 6, 7), anchor: anchor), isTrue);
        expect(rule.occursOn(DateTime(2024, 6, 8), anchor: anchor), isFalse);
        expect(rule.occursOn(DateTime(2024, 6, 9), anchor: anchor), isFalse);
      });

      test('timesPerWeek is true every day', () {
        final rule = RecurrenceRule.timesPerWeek(3);
        final anchor = DateTime(2024, 6, 1);
        for (int i = 0; i < 7; i++) {
          expect(
            rule.occursOn(anchor.add(Duration(days: i)), anchor: anchor),
            isTrue,
          );
        }
      });

      test('everyNDays respects anchor and interval', () {
        final rule = RecurrenceRule.everyNDays(2);
        final anchor = DateTime(2024, 6, 1);

        expect(rule.occursOn(DateTime(2024, 6, 1), anchor: anchor), isTrue);
        expect(rule.occursOn(DateTime(2024, 6, 2), anchor: anchor), isFalse);
        expect(rule.occursOn(DateTime(2024, 6, 3), anchor: anchor), isTrue);
        expect(rule.occursOn(DateTime(2024, 6, 5), anchor: anchor), isTrue);
        expect(rule.occursOn(DateTime(2024, 6, 7), anchor: anchor), isTrue);
        expect(rule.occursOn(DateTime(2024, 6, 8), anchor: anchor), isFalse);
        expect(rule.occursOn(DateTime(2024, 5, 31), anchor: anchor), isFalse);
      });
    });

    group('describe', () {
      test('returns expected strings', () {
        expect(const RecurrenceRule.none().describe(), 'Does not repeat');
        expect(const RecurrenceRule.daily().describe(), 'Every day');
        expect(
          RecurrenceRule.weekly(const {1, 3, 5}).describe(),
          'Mon, Wed, Fri',
        );
        expect(RecurrenceRule.timesPerWeek(3).describe(), '3× per week');
        expect(RecurrenceRule.everyNDays(2).describe(), 'Every 2 days');
        expect(RecurrenceRule.everyNDays(1).describe(), 'Every day');
        expect(RecurrenceRule.weekly(const {}).describe(), 'Does not repeat');
      });
    });
  });
}
