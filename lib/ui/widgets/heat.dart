import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../logic/progress_view.dart';
import '../theme/tokens.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrastRatio(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Whichever of the two text colours reads better on [bg].
Color readableOn(Color bg, AppColors c) =>
    contrastRatio(c.ink, bg) >= contrastRatio(c.onAccent, bg)
    ? c.ink
    : c.onAccent;

/// Background and text colour of a heat-map cell.
({Color bg, Color fg}) heatStyle(AppColors c, HeatLevel level) {
  Color mix(double t) => Color.lerp(c.surface, c.accent, t)!;
  final bg = switch (level) {
    HeatLevel.none => c.surface,
    HeatLevel.future => c.surface,
    HeatLevel.missed => c.sunken,
    HeatLevel.low => mix(0.2),
    HeatLevel.mid => mix(0.45),
    HeatLevel.full => c.accent,
  };
  final fg = level == HeatLevel.future
      ? c.faint
      : (level == HeatLevel.none ? c.muted : readableOn(bg, c));
  return (bg: bg, fg: fg);
}
