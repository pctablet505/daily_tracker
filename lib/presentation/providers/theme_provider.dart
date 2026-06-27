import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

class ThemeState {
  final ThemeMode themeMode;
  final bool useMaterialYou;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.useMaterialYou = true,
  });

  ThemeState copyWith({
    ThemeMode? themeMode,
    bool? useMaterialYou,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      useMaterialYou: useMaterialYou ?? this.useMaterialYou,
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(const ThemeState()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(AppConstants.prefDarkMode) ?? 0;
    final useMaterialYou =
        prefs.getBool(AppConstants.prefUseMaterialYou) ?? true;

    state = ThemeState(
      themeMode: ThemeMode.values[themeIndex],
      useMaterialYou: useMaterialYou,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.prefDarkMode, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setUseMaterialYou(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefUseMaterialYou, value);
    state = state.copyWith(useMaterialYou: value);
  }
}
