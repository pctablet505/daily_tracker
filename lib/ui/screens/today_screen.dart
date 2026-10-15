import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/day_key.dart';
import '../../data/models.dart';
import '../../data/stats.dart';
import '../../logic/logging.dart';
import '../../logic/today_view.dart';
import '../../services/photo_picker.dart';
import '../../state/providers.dart';
import '../../state/lock_controller.dart';
import '../format.dart';
import '../sheets/entry_sheets.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/day_strip.dart';
import '../widgets/habit_tiles.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));
  final _search = TextEditingController();
  final _celebrated = <DayKey>{};
  bool _searching = false;
  bool _showFinished = false;

  /// Monday of the week on the strip when moved away from the shown day's.
  DayKey? _stripWeek;

  @override
  void dispose() {
    _confetti.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toast(String message, {String? undoLabel, VoidCallback? onUndo}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message),
        // An Undo would otherwise keep it open until tapped.
        persist: false,
        action: onUndo == null
            ? null
            : SnackBarAction(label: undoLabel ?? 'Undo', onPressed: onUndo),
      ),
    );
  }

  DayKey get _day => ref.read(shownDayProvider);
  DayKey get _today => ref.read(todayProvider);

  /// Runs [job]; on failure says so and returns false.
  Future<bool> _guard(Future<void> Function() job) async {
    try {
      await job();
      return true;
    } catch (e) {
      if (mounted) _toast('That did not save. Try again.');
      debugPrint('Today action failed: $e');
      return false;
    }
  }

  void _toggle(HabitRow row) {
    HapticFeedback.lightImpact();
    _guard(() => ref.read(actionsProvider).tick(row.habit, _day));
  }

  void _slip(HabitRow row) {
    final h = row.habit;
    final day = _day;
    final wasSlipped = row.kind == RowKind.slipped;
    HapticFeedback.mediumImpact();
    _guard(() async {
      await ref.read(actionsProvider).slip(h, day);
      if (mounted) {
        _toast(
          wasSlipped
              ? 'Slip removed'
              : 'Logged a slip on ${h.name}. Tomorrow is a fresh start.',
          onUndo: () {
            if (!mounted) return;
            _guard(() => ref.read(actionsProvider).slip(h, day));
          },
        );
      }
    });
  }

  void _stayedClear(HabitRow row) {
    HapticFeedback.lightImpact();
    _guard(() => ref.read(actionsProvider).stayedClear(row.habit, _day));
  }

  Future<void> _log(HabitRow row) async {
    final h = row.habit;
    final day = _day;
    final today = _today;
    final actions = ref.read(actionsProvider);
    switch (h.logType) {
      case LogType.tick:
        return _toggle(row);
      case LogType.number:
        final v = await showNumberSheet(
          context,
          habit: h,
          day: day,
          today: today,
          current: row.entry?.value,
          lastValue: row.lastValue,
        );
        if (v != null && mounted) {
          await _guard(() => actions.logNumber(h, day, v));
        }
      case LogType.note:
        final t = await showNoteSheet(
          context,
          habit: h,
          day: day,
          today: today,
          current: row.entry?.note,
        );
        if (t != null && mounted) {
          await _guard(() => actions.logNote(h, day, t));
        }
      case LogType.photo:
        final choice = await showPhotoSheet(
          context,
          habit: h,
          hasPhoto: row.entry?.photoPath != null,
        );
        if (choice == null || !mounted) return;
        if (choice == PhotoChoice.remove) {
          await _guard(() => actions.clear(h, day));
          return;
        }
        try {
          final path = await ref
              .read(lockedProvider.notifier)
              .runExternal(
                () => ref.read(photoPickerProvider)(
                  choice == PhotoChoice.camera
                      ? PhotoSource.camera
                      : PhotoSource.gallery,
                  habitId: h.id,
                  day: day,
                ),
              );
          if (path != null && mounted) {
            await _guard(() => actions.logPhoto(h, day, path));
          }
        } catch (e) {
          if (mounted)
            _toast(
              choice == PhotoChoice.camera
                  ? 'The camera is not available. Choose from the gallery instead.'
                  : 'Could not open the gallery.',
            );
        }
    }
  }

  Future<void> _more(HabitRow row) async {
    final h = row.habit;
    final day = _day;
    final today = _today;
    final action = await showHabitMenu(
      context,
      habit: h,
      skipped: row.kind == RowKind.skipped,
      canSkip: canSkipDay(h, row.entry),
    );
    if (action == null || !mounted) return;
    final actions = ref.read(actionsProvider);
    final encodedId = Uri.encodeComponent(h.id);
    switch (action) {
      case HabitMenuAction.skip:
      case HabitMenuAction.unskip:
        await _guard(() => actions.skip(h, day));
      case HabitMenuAction.edit:
        await context.push('/habit/$encodedId/edit');
      case HabitMenuAction.details:
        await context.push('/habit/$encodedId');
      case HabitMenuAction.archive:
        final archived = await _guard(() => actions.archive(h, today));
        if (archived && mounted)
          _toast('Archived ${h.name}. Find it under Habits > Archived.');
    }
  }

  /// Today's tab is the one shown, and neither its page nor the shell around
  /// it is covered by another screen.
  bool get _inSight {
    if (!TickerMode.getValuesNotifier(context).value.enabled) return false;
    final page = ModalRoute.of(context);
    final shell = ModalRoute.of(Navigator.of(context).context);
    return (page?.isCurrent ?? true) && (shell?.isCurrent ?? true);
  }

  void _celebrateIfPerfect(
    AsyncValue<TodayView>? before,
    AsyncValue<TodayView> after,
  ) {
    final b = before?.value;
    final a = after.value;
    if (a == null || b == null || a.day != _today || b.day != a.day) return;
    if (!_inSight) return;
    if (a.summary.perfect &&
        !b.summary.perfect &&
        a.summary.done > b.summary.done &&
        _celebrated.add(a.day)) {
      if (MediaQuery.disableAnimationsOf(context)) return;
      _confetti.play();
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(todayViewProvider, _celebrateIfPerfect);
    ref.listen(shownDayProvider, (_, _) {
      if (_stripWeek != null) setState(() => _stripWeek = null);
    });
    final c = context.colors;
    final day = ref.watch(shownDayProvider);
    final today = ref.watch(todayProvider);
    final view = ref.watch(todayViewProvider);
    final ledger = ref.watch(ledgerProvider).value;
    final threshold = ref.watch(
      settingsProvider.select((s) => s.streakThreshold),
    );
    final isToday = day == today;
    final monday = _stripWeek ?? day.addDays(-(day.weekday - 1));

    return SafeArea(
      bottom: false,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Header(
                day: day,
                isToday: isToday,
                searching: _searching,
                controller: _search,
                onSearchToggle: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _search.clear();
                    ref.read(searchQueryProvider.notifier).set('');
                  }
                }),
                onQuery: (q) => ref.read(searchQueryProvider.notifier).set(q),
              ),
              if (ledger != null)
                DayStrip(
                  days: _weekDots(ledger, monday, today, threshold),
                  selected: day,
                  today: today,
                  onSelect: (d) => ref
                      .read(selectedDayProvider.notifier)
                      .select(d == today ? null : d),
                  onPreviousWeek: () =>
                      setState(() => _stripWeek = monday.addDays(-7)),
                  onNextWeek: monday.addDays(7) > today
                      ? null
                      : () => setState(() => _stripWeek = monday.addDays(7)),
                ),
              if (!isToday)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _PastBanner(
                    day: day,
                    onBack: () =>
                        ref.read(selectedDayProvider.notifier).select(null),
                  ),
                ),
              ...view.when(
                data: (v) => _body(context, v, ledger, today, threshold),
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [
                  EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load your habits',
                    message: 'Your data is safe on this phone.',
                    action: FilledButton(
                      onPressed: () => ref.invalidate(ledgerProvider),
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ExcludeSemantics(
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 24,
              gravity: 0.25,
              colors: [c.accent, c.amberInk, c.indigo, c.accentSoft],
            ),
          ),
        ],
      ),
    );
  }

  List<DayDot> _weekDots(Ledger l, DayKey monday, DayKey today, int threshold) {
    return [
      for (final d in monday.through(monday.addDays(6)))
        DayDot(
          day: d,
          fraction: summarizeDay(l, d, threshold: threshold).fraction,
          isFuture: d > today,
        ),
    ];
  }

  List<Widget> _body(
    BuildContext context,
    TodayView v,
    Ledger? ledger,
    DayKey today,
    int threshold,
  ) {
    final c = context.colors;
    if (!v.hasAnyHabit) {
      return [
        EmptyState(
          icon: Icons.spa_outlined,
          title: 'Nothing to track yet',
          message: 'Start with a few habits you want to keep. You can change all of it later.',
          action: Column(
            children: [
              FilledButton(
                onPressed: () => context.push('/habits/packs'),
                child: const Text('Pick starter habits'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/habit/new'),
                child: const Text('Add my own'),
              ),
            ],
          ),
        ),
      ];
    }
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    if (v.isEmpty && searching) {
      return [
        const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No habits match',
          message: 'Try a different word.',
        ),
      ];
    }
    final streak = ledger == null
        ? 0
        : currentStreak(ledger, today, threshold: threshold);
    final widgets = <Widget>[
      if (!searching) _SummaryCard(view: v, streak: streak),
      if (v.isEmpty)
        EmptyState(
          icon: Icons.event_available_outlined,
          title: 'Nothing planned for ${weekdayName(v.day)}',
          message: 'Habits you have set for other days are under Habits.',
        ),
    ];
    if (v.toDo.isNotEmpty) {
      widgets
        ..add(SectionHeader('To do', trailing: '${v.toDo.length} left'))
        ..add(
          _card([
            for (var i = 0; i < v.toDo.length; i++)
              HabitTile(
                key: ValueKey('todo-${v.toDo[i].habit.id}'),
                row: v.toDo[i],
                showDivider: i > 0,
                onToggle: () => _toggle(v.toDo[i]),
                onLog: () => _log(v.toDo[i]),
                onMore: () => _more(v.toDo[i]),
              ),
          ]),
        );
    } else if (!v.isEmpty &&
        v.summary.planned > 0 &&
        v.summary.perfect &&
        !searching) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            'Everything planned is done. Nice work.',
            style: AppType.body.copyWith(color: c.accentInk),
          ),
        ),
      );
    }
    if (v.stayClear.isNotEmpty) {
      // A row not checked offers "I stayed clear" as well as "Slipped".
      final unchecked = v.stayClear.any((r) => r.kind == RowKind.unchecked);
      widgets
        ..add(
          SectionHeader(
            'Staying clear',
            trailing: unchecked
                ? 'tap Slipped or I stayed clear'
                : 'tap Slipped if it happened',
          ),
        )
        ..add(
          _card([
            for (var i = 0; i < v.stayClear.length; i++)
              StayClearTile(
                key: ValueKey('clear-${v.stayClear[i].habit.id}'),
                row: v.stayClear[i],
                showDivider: i > 0,
                onSlip: () => _slip(v.stayClear[i]),
                onStayedClear: () => _stayedClear(v.stayClear[i]),
                onMore: () => _more(v.stayClear[i]),
              ),
          ]),
        );
    }
    if (v.finished.isNotEmpty) {
      widgets
        ..add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _FinishedToggle(
              count: v.finished.length,
              open: _showFinished,
              onTap: () => setState(() => _showFinished = !_showFinished),
            ),
          ),
        )
        ..add(
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: _showFinished
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _cardBox([
                      for (var i = 0; i < v.finished.length; i++)
                        HabitTile(
                          key: ValueKey('done-${v.finished[i].habit.id}'),
                          row: v.finished[i],
                          showDivider: i > 0,
                          onToggle: () => _toggle(v.finished[i]),
                          onLog: () => _log(v.finished[i]),
                          onMore: () => _more(v.finished[i]),
                        ),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        );
    }
    return widgets;
  }

  Widget _card(List<Widget> rows) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: _cardBox(rows),
  );
  Widget _cardBox(List<Widget> rows) =>
      SurfaceCard(child: Column(children: rows));
}

class _Header extends StatelessWidget {
  const _Header({
    required this.day,
    required this.isToday,
    required this.searching,
    required this.controller,
    required this.onSearchToggle,
    required this.onQuery,
  });

  final DayKey day;
  final bool isToday;
  final bool searching;
  final TextEditingController controller;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: searching
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: onQuery,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search habits',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          weekdayName(day).toUpperCase(),
                          style: AppType.overline.copyWith(
                            color: c.muted,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Text(longDate(day), style: AppType.display),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          if (!searching) ...[const SettingsButton(), const SizedBox(width: 8)],
          RoundIconButton(
            icon: searching ? Icons.close_rounded : Icons.search_rounded,
            tooltip: searching ? 'Close search' : 'Search habits',
            onPressed: onSearchToggle,
          ),
        ],
      ),
    );
  }
}

class _PastBanner extends StatelessWidget {
  const _PastBanner({required this.day, required this.onBack});
  final DayKey day;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: c.indigoSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 18, color: c.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing ${shortDate(day)}',
              style: AppType.small.copyWith(
                color: c.indigo,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onBack,
            style: TextButton.styleFrom(foregroundColor: c.indigo),
            child: const Text('Back to today'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.view, required this.streak});
  final TodayView view;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = view.summary;
    final frac = s.fraction ?? 0;
    final clearTotal = view.stayClear.length;
    final clearOk = view.stayClear
        .where((r) => r.kind == RowKind.onTrack)
        .length;
    final unchecked = view.stayClear
        .where((r) => r.kind == RowKind.unchecked)
        .length;
    final headline = s.planned == 0
        ? 'Nothing planned'
        : '${s.done} of ${s.planned} done';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: MergeSemantics(
        child: SurfaceCard(
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              ProgressRing(
                value: frac,
                size: 68,
                strokeWidth: 7,
                child: Text(
                  s.planned == 0 ? '–' : '${(frac * 100).round()}%',
                  style: AppType.heading.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline, style: AppType.title),
                    if (clearTotal > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Staying clear: $clearOk of $clearTotal on track'
                          '${unchecked > 0 ? ', $unchecked not checked' : ''}',
                          style: AppType.small.copyWith(color: c.muted),
                        ),
                      ),
                    if (streak >= 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: StreakChip(
                          label: '$streak-day streak',
                          semanticLabel: '$streak day streak',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinishedToggle extends StatelessWidget {
  const _FinishedToggle({
    required this.count,
    required this.open,
    required this.onTap,
  });
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      expanded: open,
      label: 'Done, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.sunken,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text('Done', style: AppType.button.copyWith(color: c.muted)),
                  const SizedBox(width: 8),
                  Container(
                    // Grows with large text instead of cutting the number off.
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      style: AppType.caption.copyWith(
                        color: c.onAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
