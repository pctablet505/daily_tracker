import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/day_key.dart';
import '../../data/stats.dart';
import '../../logic/progress_view.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/heat.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  DayKey? _month; // first day of the month shown; null = this month

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final threshold = ref.watch(
      settingsProvider.select((s) => s.streakThreshold),
    );
    final ledger = ref.watch(ledgerProvider);
    return SafeArea(
      bottom: false,
      child: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load your progress',
          action: FilledButton(
            onPressed: () => ref.invalidate(ledgerProvider),
            child: const Text('Try again'),
          ),
        ),
        data: (l) {
          if (l.habits.isEmpty) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Title(),
                Expanded(
                  child: EmptyState(
                    icon: Icons.bar_chart_rounded,
                    title: 'Nothing to show yet',
                    message: 'Once you have a habit and log a few days, your streaks and progress show up here.',
                  ),
                ),
              ],
            );
          }
          final currentMonth = today.monthStartPlus(0);
          final first = l.firstDay ?? today;
          final firstMonth = first.monthStartPlus(0) > currentMonth
              ? currentMonth
              : first.monthStartPlus(0);
          var shown = _month ?? currentMonth;
          if (shown > currentMonth) shown = currentMonth;
          if (shown < firstMonth) shown = firstMonth;
          final isThisMonth = shown >= currentMonth;
          final stats = progressStats(l, today, threshold: threshold);
          final to = shown.monthEnd > today ? today : shown.monthEnd;
          final attention = to < shown
              ? const <AttentionItem>[]
              : needsAttention(l, shown, to, today: today);
          final areas = to < shown
              ? const <AreaRate>[]
              : areaRates(l, shown, to);
          final canGoBack = shown > firstMonth;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _Title(),
              _MonthBar(
                title: monthTitle(shown),
                onPrev: canGoBack
                    ? () => setState(() => _month = shown.monthStartPlus(-1))
                    : null,
                onNext: isThisMonth
                    ? null
                    : () => setState(() {
                        final next = shown.monthStartPlus(1);
                        _month = next >= currentMonth ? null : next;
                      }),
              ),
              _Heatmap(
                cells: monthGrid(
                  l,
                  shown.year,
                  shown.month,
                  today: today,
                  threshold: threshold,
                ),
                today: today,
                onTap: (cell) => _openDay(context, cell, threshold),
              ),
              const _Legend(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _StatGrid(stats: stats),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  'A day keeps your streak at $threshold% or more of your planned habits. You can change this in Settings.',
                  style: AppType.small.copyWith(
                    color: context.colors.muted,
                    height: 1.4,
                  ),
                ),
              ),
              if (attention.isNotEmpty) ...[
                SectionHeader(
                  isThisMonth
                      ? 'Needs attention this month'
                      : 'Needed attention',
                ),
                _Card([
                  for (var i = 0; i < attention.length; i++)
                    _AttentionTile(
                      item: attention[i],
                      divider: i > 0,
                      onTap: () => context.push(
                        '/habit/${Uri.encodeComponent(attention[i].habit.id)}',
                      ),
                    ),
                ]),
              ],
              if (areas.length > 1) ...[
                const SectionHeader('By area'),
                _Card([
                  for (var i = 0; i < areas.length; i++)
                    _AreaBar(rate: areas[i], divider: i > 0),
                ]),
              ],
              const SectionHeader('Last 7 days'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _WeekBars(
                  days: lastDays(l, today, 7, threshold: threshold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDay(BuildContext context, DayHeat cell, int threshold) {
    final day = cell.day;
    if (day == null || cell.level == HeatLevel.future) return;
    final s = cell.summary!;
    final c = context.colors;
    final summaryText = s.planned == 0
        ? (s.slips > 0
              ? '${plural(s.slips, 'slip')} logged.'
              : 'Nothing was planned.')
        : '${s.done} of ${s.planned} done${s.slips > 0 ? ', ${plural(s.slips, 'slip')}' : ', no slips'}.';
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(shortDate(day), style: AppType.title),
              const SizedBox(height: 4),
              Text(
                summaryText,
                style: AppType.bodyLight.copyWith(color: c.muted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ref
                      .read(selectedDayProvider.notifier)
                      .select(day == ref.read(todayProvider) ? null : day);
                  context.go('/');
                },
                child: Text(
                  day == ref.read(todayProvider)
                      ? 'Open today'
                      : 'Open or fix this day',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    // Inside a list the title and the button would merge into one screen-reader stop.
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text('Progress', style: AppType.display),
            ),
          ),
          const SettingsButton(),
        ],
      ),
    ),
  );
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.title,
    required this.onPrev,
    required this.onNext,
  });
  final String title;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.heading,
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({
    required this.cells,
    required this.today,
    required this.onTap,
  });
  final List<DayHeat> cells;
  final DayKey today;
  final ValueChanged<DayHeat> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final rows = <List<DayHeat?>>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add([
        for (var j = i; j < i + 7; j++) j < cells.length ? cells[j] : null,
      ]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                for (final l in letters)
                  Expanded(
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          l,
                          style: AppType.caption.copyWith(
                            color: c.faint,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    for (final cell in r)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: cell == null || cell.day == null
                              ? const SizedBox(height: 40)
                              : _Cell(
                                  cell: cell,
                                  isToday: cell.day == today,
                                  onTap: () => onTap(cell),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell, required this.isToday, required this.onTap});
  final DayHeat cell;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = heatStyle(c, cell.level);
    final s = cell.summary!;
    final detail = switch (cell.level) {
      HeatLevel.future => 'not yet',
      HeatLevel.none => 'nothing planned',
      _ =>
        s.planned == 0
            ? (s.slips > 0 ? plural(s.slips, 'slip') : 'on track')
            : '${s.done} of ${s.planned} done',
    };
    return Semantics(
      button: cell.level != HeatLevel.future,
      label: '${isToday ? 'Today, ' : ''}${longDate(cell.day!)}, $detail',
      excludeSemantics: true,
      onTap: cell.level == HeatLevel.future ? null : onTap,
      child: Material(
        color: style.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isToday
                ? c.ink
                : (cell.level == HeatLevel.none ||
                          cell.level == HeatLevel.future ||
                          cell.level == HeatLevel.missed
                      ? c.border
                      : style.bg),
            width: isToday ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: cell.level == HeatLevel.future ? null : onTap,
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                '${cell.day!.day}',
                style: AppType.small.copyWith(
                  color: style.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less ', style: AppType.caption.copyWith(color: c.muted)),
            for (final l in [
              HeatLevel.missed,
              HeatLevel.low,
              HeatLevel.mid,
              HeatLevel.full,
            ])
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: heatStyle(c, l).bg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: c.border),
                ),
              ),
            Text(' More', style: AppType.caption.copyWith(color: c.muted)),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final pct = stats.rate30.fraction == null
        ? '–'
        : '${(stats.rate30.fraction! * 100).round()}%';
    final tiles = [
      ('${stats.currentStreak}', 'Day streak'),
      ('${stats.bestStreak}', 'Best streak'),
      (pct, 'Last 30 days'),
      ('${stats.perfectDays}', 'Perfect days'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in tiles)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 40 - 10) / 2,
            child: MergeSemantics(
              child: SurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.$1, style: appText(28, 800, height: 1.15)),
                    Text(
                      t.$2,
                      style: AppType.small.copyWith(
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: SurfaceCard(child: Column(children: children)),
  );
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.item,
    required this.divider,
    required this.onTap,
  });
  final AttentionItem item;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: c.border)) : null,
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.habit.name, style: AppType.body),
                      Text(
                        '${item.ratio.done} of ${item.ratio.planned} days',
                        style: AppType.caption.copyWith(color: c.faint),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(item.ratio.fraction! * 100).round()}%',
                  style: AppType.heading.copyWith(color: c.amberInk),
                ),
                Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaBar extends StatelessWidget {
  const _AreaBar({required this.rate, required this.divider});
  final AreaRate rate;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = rate.ratio.fraction ?? 0;
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: divider ? Border(top: BorderSide(color: c.border)) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(rate.area, style: AppType.body)),
                  Text(
                    '${(f * 100).round()}%',
                    style: AppType.small.copyWith(
                      color: c.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: f,
                  minHeight: 10,
                  backgroundColor: c.sunken,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});
  final List<DaySummary> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in days)
              Expanded(
                child: Semantics(
                  label:
                      '${longDate(d.day)}, ${d.planned == 0 ? 'nothing planned' : '${d.done} of ${d.planned} done'}',
                  excludeSemantics: true,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: (d.fraction ?? 0).clamp(0.04, 1),
                            widthFactor: 0.5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: d.planned == 0 ? c.border : c.accent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        weekdayLetter(d.day),
                        style: AppType.caption.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
