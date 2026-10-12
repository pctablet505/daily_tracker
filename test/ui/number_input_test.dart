import 'package:daily_tracker/ui/number_input.dart';
import 'package:flutter_test/flutter_test.dart';

NumberInput typed(String keys, [NumberInput? from]) {
  var n = from ?? const NumberInput();
  for (final k in keys.split('')) {
    n = n.press(k);
  }
  return n;
}

void main() {
  test('starts empty with no value', () {
    expect(const NumberInput().text, '');
    expect(const NumberInput().value, isNull);
  });

  test('digits build the number', () {
    expect(typed('755').value, 755);
    expect(typed('75.5').text, '75.5');
    expect(typed('75.5').value, 75.5);
  });

  test('only one decimal point; a leading point gets a zero', () {
    expect(typed('7.5.2').text, '7.52');
    expect(typed('.5').text, '0.5');
  });

  test('a leading zero is replaced by the next digit, but 0.x stays', () {
    expect(typed('05').text, '5');
    expect(typed('007').text, '7');
    expect(typed('0.5').text, '0.5');
    expect(typed('0').text, '0');
  });

  test('at most two decimals and seven digits', () {
    expect(typed('1.2345').text, '1.23');
    expect(typed('123456789').text, '1234567');
    expect(typed('1234567.1').text, '1234567.1');
  });

  test('backspace removes the last character and is safe when empty', () {
    expect(typed('75.5').press('back').text, '75.');
    expect(typed('7').press('back').text, '');
    expect(const NumberInput().press('back').text, '');
  });

  test('a lone point is not a value', () {
    expect(typed('.').text, '0.');
    expect(typed('.').value, 0);
    expect(const NumberInput('.').value, isNull);
  });

  test('anything that is not a key is ignored', () {
    expect(typed('7').press('x').text, '7');
    expect(typed('7').press('').text, '7');
  });

  group('adjust', () {
    test('adds a step without float noise', () {
      expect(NumberInput('75.5').adjust(0.1).text, '75.6');
      expect(NumberInput('0.1').adjust(0.2).text, '0.3');
      expect(NumberInput('3').adjust(1).text, '4');
    });

    test('starts from zero when empty, and never goes below zero or above max', () {
      expect(const NumberInput().adjust(1).text, '1');
      expect(NumberInput('0.3').adjust(-1).text, '0');
      expect(const NumberInput().adjust(-1).text, '0');
      expect(const NumberInput('9999999').adjust(10).text, '9999999.99');
      expect(plainAmount(-0.0), '0');
    });
  });

  group('step', () {
    test(
      'is 1 for whole amounts and 0.1 when the amount or goal has decimals',
      () {
        expect(stepFor(goal: 8, lastValue: null, current: null), 1);
        expect(stepFor(goal: null, lastValue: 75.9, current: null), 0.1);
        expect(stepFor(goal: 2.5, lastValue: null, current: null), 0.1);
        expect(stepFor(goal: null, lastValue: null, current: 75.5), 0.1);
        expect(stepFor(goal: null, lastValue: null, current: null), 1);
      },
    );
  });
}
