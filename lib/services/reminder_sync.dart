import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'reminder_plan.dart';

/// Keeps the scheduled notifications in line with the habits and settings: after
/// any change it rebuilds the plan and replaces what the phone has scheduled.
class ReminderSync {
  ReminderSync(this._ref) {
    _ref.listen(revisionProvider, (_, _) => _schedule());
    _ref.listen(settingsProvider, (_, _) => _schedule());
    _ref.listen(todayProvider, (_, _) => _schedule());
    _ref.onDispose(() => _debounce?.cancel());
    _schedule();
  }

  /// How many days ahead are scheduled. The app re-plans each time it opens.
  static const horizonDays = 14;

  final Ref _ref;
  Timer? _debounce;
  Future<void>? _running;

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(resync()),
    );
  }

  /// Rebuilds and applies the plan now. Does nothing without notification permission.
  Future<void> resync() {
    // Run one at a time; a call that arrives meanwhile runs after the current one.
    final previous = _running ?? Future<void>.value();
    final next = previous.then((_) => _run());
    _running = next.whenComplete(() {
      if (identical(_running, next)) _running = null;
    });
    return next;
  }

  Future<void> _run() async {
    try {
      final ledger = await _ref.read(ledgerProvider.future);
      final scheduler = _ref.read(reminderSchedulerProvider);
      if (!await scheduler.hasPermission()) return;
      final plan = planReminders(
        ledger,
        settings: _ref.read(settingsProvider),
        now: _ref.read(clockProvider)(),
        horizonDays: horizonDays,
      );
      await scheduler.replaceAll(plan);
    } catch (e) {
      debugPrint('Rescheduling reminders failed: $e');
    }
  }
}

final reminderSyncProvider = Provider<ReminderSync>((ref) => ReminderSync(ref));
