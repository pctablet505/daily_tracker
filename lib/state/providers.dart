import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/day_key.dart';
import '../data/repository.dart';
import '../data/stats.dart';
import '../logic/today_view.dart';
import '../services/notifications.dart';
import '../services/photo_store.dart';
import 'actions.dart';
import 'settings.dart';

/// Set in `main` (and in tests) before anything reads them.
final databaseProvider = Provider<Database>(
  (ref) => throw UnimplementedError('databaseProvider is not set'),
);
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider is not set'),
);

final photoStoreProvider = Provider<PhotoStore>(
  (ref) => throw UnimplementedError('photoStoreProvider is not set'),
);

/// The current time. Tests replace it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Counts writes. Anything that reads stored data watches it, so no screen goes stale.
class RevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final revisionProvider = NotifierProvider<RevisionNotifier, int>(
  RevisionNotifier.new,
);

final repositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(
    ref.watch(databaseProvider),
    onChanged: () {
      if (ref.mounted) ref.read(revisionProvider.notifier).bump();
    },
  );
});

/// Today's calendar day. It moves on by itself at local midnight, and
/// [refresh] (called when the app returns to the foreground) catches a missed
/// timer or a changed clock or time zone.
class TodayNotifier extends Notifier<DayKey> {
  Timer? _timer;

  @override
  DayKey build() {
    ref.onDispose(() => _timer?.cancel());
    final now = ref.read(clockProvider)();
    _schedule(now);
    return DayKey.fromDate(now);
  }

  void _schedule(DateTime now) {
    _timer?.cancel();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 1),
      refresh,
    );
  }

  void refresh() {
    final now = ref.read(clockProvider)();
    _schedule(now);
    final today = DayKey.fromDate(now);
    if (today != state) state = today;
  }
}

final todayProvider = NotifierProvider<TodayNotifier, DayKey>(
  TodayNotifier.new,
);

class SettingsNotifier extends Notifier<Settings> {
  Future<void>? _writing;

  @override
  Settings build() => Settings.read(ref.read(sharedPrefsProvider));

  Future<void> update(Settings Function(Settings) change) {
    final next = change(state);
    if (next == state) return _writing ?? Future<void>.value();
    state = next;
    final prefs = ref.read(sharedPrefsProvider);
    final prev = _writing ?? Future<void>.value();
    final run = prev.then((_) => next.write(prefs));
    _writing = run.whenComplete(() {
      if (identical(_writing, run)) _writing = null;
    });
    return run;
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

/// Everything stored, ready for the counting functions. Rebuilt after every write.
final ledgerProvider = FutureProvider<Ledger>((ref) async {
  ref.watch(revisionProvider);
  final snap = await ref.watch(repositoryProvider).snapshot();
  return Ledger(
    habits: snap.habits,
    entries: snap.entries,
    seenDays: snap.seenDays,
  );
});

/// A day picked on the week strip; null follows today.
class SelectedDayNotifier extends Notifier<DayKey?> {
  @override
  DayKey? build() => null;

  void select(DayKey? day) => state = day;
}

final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DayKey?>(
  SelectedDayNotifier.new,
);

/// The day the Today screen shows.
final shownDayProvider = Provider<DayKey>(
  (ref) => ref.watch(selectedDayProvider) ?? ref.watch(todayProvider),
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final todayViewProvider = Provider<AsyncValue<TodayView>>((ref) {
  final day = ref.watch(shownDayProvider);
  final query = ref.watch(searchQueryProvider);
  final threshold = ref.watch(
    settingsProvider.select((s) => s.streakThreshold),
  );
  final photos = ref.watch(photoStoreProvider);
  return ref
      .watch(ledgerProvider)
      .whenData(
        (l) => buildTodayView(
          l,
          day,
          query: query,
          threshold: threshold,
          photoExists: photos.exists,
        ),
      );
});

final actionsProvider = Provider<HabitActions>((ref) {
  return HabitActions(
    repo: ref.watch(repositoryProvider),
    photos: ref.watch(photoStoreProvider),
    now: ref.watch(clockProvider),
    newId: () => const Uuid().v4(),
  );
});

/// Set in `main`; tests replace it with a fake.
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => throw UnimplementedError('reminderSchedulerProvider is not set'),
);
