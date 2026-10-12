import 'package:flutter/material.dart';

/// The app's colours. Teal-green means done, amber a streak, indigo staying
/// clear (never red, which reads as failure). Text pairs are checked for
/// WCAG AA contrast in `test/ui/contrast_test.dart`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.border,
    required this.border2,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentInk,
    required this.amberInk,
    required this.amberSoft,
    required this.indigo,
    required this.indigoSoft,
    required this.todayTrack,
    required this.danger,
  });

  final Color bg;
  final Color surface;
  final Color sunken;
  final Color border;

  /// Borders of controls (checkboxes, outlined buttons): strong enough to see.
  final Color border2;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color accentInk;
  final Color amberInk;
  final Color amberSoft;
  final Color indigo;
  final Color indigoSoft;
  final Color todayTrack;

  /// Only for destructive actions (delete, replace all data).
  final Color danger;

  static const light = AppColors(
    bg: Color(0xFFF3F5F2),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFE8EDE8),
    border: Color(0xFFDCE2DC),
    border2: Color(0xFF7A8982),
    ink: Color(0xFF14201B),
    muted: Color(0xFF4B5B53),
    faint: Color(0xFF5F6E66),
    accent: Color(0xFF0B6B57),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFD9EFE6),
    accentInk: Color(0xFF0A5545),
    amberInk: Color(0xFF7A4300),
    amberSoft: Color(0xFFFFEFD2),
    indigo: Color(0xFF3A4899),
    indigoSoft: Color(0xFFE4E8F9),
    todayTrack: Color(0x59FFFFFF),
    danger: Color(0xFFA32D2D),
  );

  static const dark = AppColors(
    bg: Color(0xFF0E1411),
    surface: Color(0xFF17201B),
    sunken: Color(0xFF111A15),
    border: Color(0xFF27332C),
    border2: Color(0xFF6F8077),
    ink: Color(0xFFE9F0EB),
    muted: Color(0xFFA5B4AB),
    faint: Color(0xFF8C9B92),
    accent: Color(0xFF4CCFAA),
    onAccent: Color(0xFF06271E),
    accentSoft: Color(0xFF1B3A31),
    accentInk: Color(0xFF8EE6CB),
    amberInk: Color(0xFFF0B968),
    amberSoft: Color(0xFF3A2B12),
    indigo: Color(0xFFAEB8F7),
    indigoSoft: Color(0xFF252B4F),
    todayTrack: Color(0x4D06271E),
    danger: Color(0xFFF2A0A0),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      sunken: l(sunken, other.sunken),
      border: l(border, other.border),
      border2: l(border2, other.border2),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      accentInk: l(accentInk, other.accentInk),
      amberInk: l(amberInk, other.amberInk),
      amberSoft: l(amberSoft, other.amberSoft),
      indigo: l(indigo, other.indigo),
      indigoSoft: l(indigoSoft, other.indigoSoft),
      todayTrack: l(todayTrack, other.todayTrack),
      danger: l(danger, other.danger),
    );
  }
}

extension AppColorsOf on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Plus Jakarta Sans is a variable font; the weight is set on both the
/// `FontWeight` and the `wght` axis so every weight renders distinctly.
TextStyle appText(
  double size,
  int weight, {
  double? height,
  double? letterSpacing,
  Color? color,
}) {
  final w = FontWeight.values[((weight ~/ 100) - 1).clamp(0, 8)];
  return TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: size,
    fontWeight: w,
    fontVariations: [FontVariation('wght', weight.toDouble())],
    height: height ?? 1.3,
    letterSpacing: letterSpacing,
    color: color,
  );
}

/// The type scale. Colours come from the surrounding theme.
abstract final class AppType {
  static final display = appText(
    28,
    800,
    height: 34 / 28,
    letterSpacing: -0.28,
  );
  static final title = appText(20, 800, height: 24 / 20);
  static final heading = appText(17, 700, height: 22 / 17);
  static final body = appText(16, 600, height: 20 / 16);
  static final bodyLight = appText(15, 500, height: 20 / 15);
  static final small = appText(13, 500, height: 18 / 13);
  static final caption = appText(12, 500, height: 16 / 12);
  static final overline = appText(12, 800, height: 16 / 12, letterSpacing: 0.9);
  static final button = appText(15, 700, height: 20 / 15);
}
