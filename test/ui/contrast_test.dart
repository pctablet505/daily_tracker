import 'dart:math' as math;

import 'package:daily_tracker/logic/progress_view.dart';
import 'package:daily_tracker/ui/theme/tokens.dart';
import 'package:daily_tracker/ui/widgets/heat.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double ratio(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final entry in {
    'light': AppColors.light,
    'dark': AppColors.dark,
  }.entries) {
    final c = entry.value;
    final name = entry.key;

    // Text must reach 4.5:1 (WCAG AA); borders of controls 3:1.
    final text = <String, (Color, Color)>{
      'ink on bg': (c.ink, c.bg),
      'ink on surface': (c.ink, c.surface),
      'muted on bg': (c.muted, c.bg),
      'muted on surface': (c.muted, c.surface),
      'muted on sunken': (c.muted, c.sunken),
      'faint on surface': (c.faint, c.surface),
      'faint on bg': (c.faint, c.bg),
      'onAccent on accent': (c.onAccent, c.accent),
      'accentInk on accentSoft': (c.accentInk, c.accentSoft),
      'accentInk on surface': (c.accentInk, c.surface),
      'accentInk on bg': (c.accentInk, c.bg),
      'amberInk on amberSoft': (c.amberInk, c.amberSoft),
      'indigo on indigoSoft': (c.indigo, c.indigoSoft),
      'indigo on surface': (c.indigo, c.surface),
      'danger on surface': (c.danger, c.surface),
      'danger on bg': (c.danger, c.bg),
    };
    for (final t in text.entries) {
      test('$name: ${t.key} reaches 4.5:1', () {
        expect(ratio(t.value.$1, t.value.$2), greaterThanOrEqualTo(4.5));
      });
    }

    final ui = <String, (Color, Color)>{
      'border2 on surface': (c.border2, c.surface),
      'border2 on bg': (c.border2, c.bg),
      'accent on surface': (c.accent, c.surface),
      'accent on bg': (c.accent, c.bg),
    };
    for (final t in ui.entries) {
      test('$name: ${t.key} reaches 3:1', () {
        expect(ratio(t.value.$1, t.value.$2), greaterThanOrEqualTo(3));
      });
    }
  }

  test('snackbar action text is readable on the snackbar background', () {
    expect(
      ratio(AppColors.dark.accent, AppColors.light.ink),
      greaterThanOrEqualTo(4.5),
    ); // light theme
    expect(
      ratio(AppColors.light.accent, AppColors.dark.ink),
      greaterThanOrEqualTo(4.5),
    ); // dark theme
  });

  for (final entry in {
    'light': AppColors.light,
    'dark': AppColors.dark,
  }.entries) {
    for (final level in HeatLevel.values) {
      test(
        '${entry.key}: the day number on a ${level.name} heat-map cell reaches 4.5:1',
        () {
          final s = heatStyle(entry.value, level);
          expect(ratio(s.fg, s.bg), greaterThanOrEqualTo(4.5));
        },
      );
    }
    test('${entry.key}: heat levels are distinct from each other', () {
      final colors = [
        for (final l in [
          HeatLevel.missed,
          HeatLevel.low,
          HeatLevel.mid,
          HeatLevel.full,
        ])
          heatStyle(entry.value, l).bg,
      ];
      expect(colors.toSet().length, 4);
    });
  }
}
