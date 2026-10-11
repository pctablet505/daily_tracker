import 'format.dart';

/// The text behind the on-screen keypad. Immutable: each key press returns a new one.
final class NumberInput {
  const NumberInput([this.text = '']);

  static const maxDigits = 7;
  static const maxDecimals = 2;

  final String text;

  /// The number typed so far, or null when there is none yet.
  double? get value => double.tryParse(text);

  NumberInput press(String key) {
    if (key == 'back') return NumberInput(text.isEmpty ? '' : text.substring(0, text.length - 1));
    if (key == '.') {
      if (text.contains('.')) return this;
      return NumberInput(text.isEmpty ? '0.' : '$text.');
    }
    if (key.length != 1 || !'0123456789'.contains(key)) return this;
    final dot = text.indexOf('.');
    if (dot >= 0) {
      return text.length - dot - 1 >= maxDecimals ? this : NumberInput('$text$key');
    }
    if (text.length >= maxDigits) return this;
    return NumberInput(text == '0' ? key : '$text$key');
  }

  /// Add [delta] (may be negative); the result is not below zero and has no float noise.
  NumberInput adjust(double delta) {
    final next = ((value ?? 0) + delta).clamp(0, double.infinity).toDouble();
    return NumberInput(formatAmount(double.parse(next.toStringAsFixed(2))));
  }
}

/// The size of the plus/minus buttons: 0.1 when amounts carry decimals, else 1.
double stepFor({required double? goal, required double? lastValue, required double? current}) {
  bool hasDecimals(double? v) => v != null && v != v.roundToDouble();
  return hasDecimals(goal) || hasDecimals(lastValue) || hasDecimals(current) ? 0.1 : 1;
}
