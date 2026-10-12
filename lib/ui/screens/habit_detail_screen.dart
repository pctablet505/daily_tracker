import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../logic/habit_detail.dart';
import '../../services/photo_store.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class HabitDetailScreen extends ConsumerWidget {
  const HabitDetailScreen({super.key, required this.habitId});
  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    final today = ref.watch(todayProvider);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    return ledger.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load this habit',
        ),
      ),
      data: (l) {
        final h = l.habits.where((x) => x.id == habitId).firstOrNull;
        if (h == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'This habit no longer exists',
            ),
          );
        }
        final d = buildHabitDetail(l, h, today);
        return Scaffold(
          appBar: AppBar(
            title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Edit habit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/habit/${h.id}/edit'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _Facts(habit: h, use24h: use24h),
              const SizedBox(height: 16),
              _Stats(habit: h, detail: d),
              if (h.logType == LogType.number && d.series.isNotEmpty) ...[
                const SectionHeader(
                  'Trend',
                  padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
                ),
                _Trend(habit: h, detail: d),
              ],
              const SectionHeader(
                'Last 12 weeks',
                padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
              ),
              _Grid(days: d.recentDays),
              if (d.photos.isNotEmpty) ...[
                SectionHeader(
                  'Photos, ${d.photos.length}',
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
                ),
                _Photos(entries: d.photos.take(30).toList()),
              ],
              if (d.recent.isNotEmpty) ...[
                const SectionHeader(
                  'Recent entries',
                  padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
                ),
                SurfaceCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < d.recent.length; i++)
                        _EntryTile(
                          habit: h,
                          entry: d.recent[i],
                          previous: d.recent
                              .skip(i + 1)
                              .where(
                                (e) =>
                                    e.state != EntryState.skipped &&
                                    e.value != null,
                              )
                              .firstOrNull,
                          divider: i > 0,
                          onTap: () {
                            ref
                                .read(selectedDayProvider.notifier)
                                .select(
                                  d.recent[i].day == today
                                      ? null
                                      : d.recent[i].day,
                                );
                            context.go('/');
                          },
                        ),
                    ],
                  ),
                ),
              ],
              if (d.recent.isEmpty)
                const EmptyState(
                  icon: Icons.insights_outlined,
                  title: 'No entries yet',
                  message:
                      'Log this habit on Today and its history builds up here.',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.habit, required this.use24h});
  final Habit habit;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final facts = <String>[
      habit.tracksSlips
          ? 'Staying clear'
          : (habit.kind == HabitKind.avoid ? 'Avoid, tick each day' : 'Do'),
      if (!habit.tracksSlips) scheduleSummary(habit.daysMask),
      dayPartName(habit.dayPart),
      if (habit.reminderMinutes != null)
        'Reminder ${formatMinutes(habit.reminderMinutes!, use24h: use24h)}',
      if (habit.area != null) habit.area!,
      if (habit.isArchived) 'Archived ${shortDate(habit.endDay!)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in facts)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: c.sunken,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  f,
                  style: AppType.caption.copyWith(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        if (habit.description != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              habit.description!,
              style: AppType.bodyLight.copyWith(color: c.muted, height: 1.4),
            ),
          ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.habit, required this.detail});
  final Habit habit;
  final HabitDetail detail;

  @override
  Widget build(BuildContext context) {
    final r = detail.rate30.fraction;
    final tiles = [
      (
        '${detail.streak.current}',
        habit.tracksSlips ? 'Days clear' : 'Day streak',
      ),
      ('${detail.streak.best}', 'Best streak'),
      (r == null ? '–' : '${(r * 100).round()}%', 'Last 30 days'),
      (
        habit.tracksSlips
            ? '${detail.recent.where((e) => e.state == EntryState.slipped).length}'
            : '${detail.totalDone}',
        habit.tracksSlips ? 'Slips (recent)' : 'Times done',
      ),
    ];
    final w = (MediaQuery.sizeOf(context).width - 40 - 10) / 2;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in tiles)
          SizedBox(
            width: w,
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

class _Trend extends StatelessWidget {
  const _Trend({required this.habit, required this.detail});
  final Habit habit;
  final HabitDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pts = detail.series.length > 60
        ? detail.series.sublist(detail.series.length - 60)
        : detail.series;
    final first = pts.first.day;
    final spots = [
      for (final p in pts) FlSpot(first.daysUntil(p.day).toDouble(), p.value),
    ];
    final values = pts.map((p) => p.value);
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) == 0
        ? (maxY.abs() * 0.05 + 1)
        : (maxY - minY) * 0.2;
    minY -= pad;
    maxY += pad;
    final change = detail.change30;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: MergeSemantics(
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formatAmount(detail.latest!),
                          style: appText(32, 800, height: 1.15),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          habit.unit ?? '',
                          style: AppType.body.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                    if (change != null)
                      Text(
                        '${change > 0
                                ? '+'
                                : change < 0
                                ? '−'
                                : ''}${formatAmount(change.abs())} ${habit.unit ?? ''} in 30 days'
                            .trim(),
                        style: AppType.small.copyWith(
                          color: c.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            label:
                'Chart of ${habit.name} over time. Latest ${formatAmountUnit(detail.latest!, habit.unit)}.',
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: spots.last.x == 0 ? 1 : spots.last.x,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: c.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        maxIncluded: false,
                        minIncluded: false,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            formatAmount(double.parse(v.toStringAsFixed(1))),
                            style: AppType.caption.copyWith(color: c.faint),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        maxIncluded: false,
                        interval: spots.last.x < 6
                            ? 1
                            : (spots.last.x / 4).ceilToDouble(),
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            shortDate(first.addDays(v.round()))
                                .split(' ')
                                .skip(1)
                                .join(' '),
                            style: AppType.caption.copyWith(color: c.faint),
                          ),
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: spots.length > 2,
                      curveSmoothness: 0.2,
                      preventCurveOverShooting: true,
                      color: c.accent,
                      barWidth: 3,
                      dotData: FlDotData(show: spots.length <= 31),
                      belowBarData: BarAreaData(
                        show: true,
                        color: c.accent.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.days});
  final List<HabitDayDot> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Columns are weeks, rows are weekdays (Monday on top); pad the first week.
    final lead = days.first.day.weekday - 1;
    final cells = <HabitDayDot?>[for (var i = 0; i < lead; i++) null, ...days];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = cells.length ~/ 7;
    Color colorOf(DotState s) => switch (s) {
      DotState.done => c.accent,
      DotState.missed => c.sunken,
      DotState.skipped => c.amberSoft,
      DotState.pending => c.surface,
      DotState.none => Colors.transparent,
    };
    final done = days.where((d) => d.state == DotState.done).length;
    final missed = days.where((d) => d.state == DotState.missed).length;
    return Semantics(
      label: 'Last 12 weeks: $done days done, $missed missed.',
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = ((box.maxWidth - (weeks - 1) * 3) / weeks).clamp(
                8.0,
                18.0,
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var w = 0; w < weeks; w++)
                    Padding(
                      padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : 3),
                      child: Column(
                        children: [
                          for (var r = 0; r < 7; r++)
                            Container(
                              width: size,
                              height: size,
                              margin: const EdgeInsets.only(bottom: 3),
                              decoration: BoxDecoration(
                                color: cells[w * 7 + r] == null
                                    ? Colors.transparent
                                    : colorOf(cells[w * 7 + r]!.state),
                                borderRadius: BorderRadius.circular(3),
                                border:
                                    cells[w * 7 + r] != null &&
                                        cells[w * 7 + r]!.state != DotState.none
                                    ? Border.all(color: c.border)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Photos extends ConsumerWidget {
  const _Photos({required this.entries});
  final List<Entry> entries;

  void _open(BuildContext context, PhotoStore store, Entry e) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(
                  store.fileFor(e.photoPath!),
                  errorBuilder: (_, _, _) => const _MissingPhoto(big: true),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Text(
                    shortDate(e.day),
                    style: AppType.heading.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final store = ref.watch(photoStoreProvider);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final e in entries)
          Semantics(
            button: true,
            label: 'Photo from ${shortDate(e.day)}',
            excludeSemantics: true,
            onTap: () => _open(context, store, e),
            child: GestureDetector(
              onTap: () => _open(context, store, e),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  store.fileFor(e.photoPath!),
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: c.sunken, child: const _MissingPhoto()),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MissingPhoto extends StatelessWidget {
  const _MissingPhoto({this.big = false});
  final bool big;

  @override
  Widget build(BuildContext context) {
    final color = big ? Colors.white70 : context.colors.faint;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: color),
          if (big)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'This photo is not on this phone. Backups do not include photos.',
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: color),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.habit,
    required this.entry,
    required this.previous,
    required this.divider,
    required this.onTap,
  });
  final Habit habit;
  final Entry entry;
  final Entry? previous;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = entry.state == EntryState.skipped ? null : entry.value;
    final delta = v != null && previous?.value != null
        ? v - previous!.value!
        : null;
    final title = switch (entry.state) {
      EntryState.slipped => 'Slipped',
      EntryState.skipped => 'Skipped',
      _ =>
        v != null
            ? formatAmountUnit(v, habit.unit)
            : (entry.note ?? (entry.photoPath != null ? 'Photo' : 'Done')),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: c.border)) : null,
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    shortDate(entry.day),
                    style: AppType.small.copyWith(color: c.muted),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: AppType.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (delta != null && delta != 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '${delta > 0 ? '+' : '−'}${formatAmount(double.parse(delta.abs().toStringAsFixed(2)))}',
                      style: AppType.caption.copyWith(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
