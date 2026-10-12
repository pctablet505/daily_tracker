import 'dart:ui' show Tristate;

import 'package:daily_tracker/ui/theme/theme.dart';
import 'package:daily_tracker/ui/widgets/keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  setUpAll(loadAppFont);

  testWidgets(
    'a key calls its own handler and has its own screen-reader label',
    (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(
        _host(
          Keypad(
            keys: [
              PadKey.digit('1', () => pressed.add('1')),
              PadKey('Decimal point', () => pressed.add('.'), text: '.'),
              PadKey.backspace(() => pressed.add('back')),
            ],
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Digit 1'));
      await tester.tap(find.bySemanticsLabel('Decimal point'));
      await tester.tap(find.bySemanticsLabel('Delete last digit'));

      expect(pressed, ['1', '.', 'back']);
    },
  );

  testWidgets('a key without a handler does nothing and says it is disabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _host(
        Keypad(
          keys: [
            PadKey('Save', null, icon: Icons.check_rounded, primary: true),
            PadKey.digit('2', () => taps++),
          ],
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Save'), warnIfMissed: false);
    final save = tester.getSemantics(find.bySemanticsLabel('Save'));
    expect(taps, 0);
    expect(save.getSemanticsData().flagsCollection.isEnabled, Tristate.isFalse);

    await tester.tap(find.bySemanticsLabel('Digit 2'));
    expect(taps, 1);
    handle.dispose();
  });
}
