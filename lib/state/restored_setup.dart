import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import 'settings.dart';

/// Android's cloud backup carries the database but not the settings, so a restored phone
/// has its habits and no record that the first-run screen was done. Habits mean the app
/// was set up (archived ones count: they were habits once), so record it; otherwise the
/// first-run screen, whose starter packs would duplicate them, shows up again.
///
/// A database that cannot be read leaves the flag alone: the app must still start.
Future<void> markSetUpIfHabitsExist(
  HabitRepository repo,
  SharedPreferences prefs,
) async {
  final settings = Settings.read(prefs);
  if (settings.onboardingDone) return;
  try {
    if ((await repo.habits()).isEmpty) return;
  } catch (_) {
    return;
  }
  await settings.copyWith(onboardingDone: true).write(prefs);
}
