import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accentSoft,
    onSecondary: c.accentInk,
    error: c.danger,
    onError: c.onAccent,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.sunken,
    outline: c.border2,
    outlineVariant: c.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'PlusJakartaSans',
  );
  // Colours are applied last: the AppType styles carry none of their own.
  final text = base.textTheme
      .copyWith(
        bodyLarge: AppType.body,
        bodyMedium: AppType.bodyLight,
        bodySmall: AppType.small,
        titleLarge: AppType.title,
        titleMedium: AppType.heading,
        titleSmall: AppType.body,
        labelLarge: AppType.button,
        labelMedium: AppType.caption,
        labelSmall: AppType.caption,
        headlineMedium: AppType.display,
      )
      .apply(bodyColor: c.ink, displayColor: c.ink);
  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    textTheme: text,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppType.title.copyWith(color: c.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      showDragHandle: true,
      dragHandleColor: c.border2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: AppType.title.copyWith(color: c.ink),
      contentTextStyle: AppType.bodyLight.copyWith(color: c.muted, height: 1.4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: AppType.body.copyWith(color: c.bg),
      actionTextColor: brightness == Brightness.dark
          ? AppColors.light.accent
          : AppColors.dark.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.border2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.sunken,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.border2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: AppType.bodyLight.copyWith(color: c.faint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger, width: 2),
      ),
      errorStyle: AppType.small.copyWith(color: c.danger),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: AppType.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: c.border2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: AppType.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentInk,
        minimumSize: const Size(48, 48),
        textStyle: AppType.button,
      ),
    ),
  );
}
