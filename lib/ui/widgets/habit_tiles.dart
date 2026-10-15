import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../logic/today_view.dart';
import '../format.dart';
import '../theme/tokens.dart';
import 'common.dart';

IconData logIcon(LogType t) => switch (t) {
  LogType.number => Icons.straighten_rounded,
  LogType.note => Icons.edit_note_rounded,
  LogType.photo => Icons.photo_camera_outlined,
  LogType.tick => Icons.check_rounded,
};

/// The round control at the start of a to-do row.
class _Mark extends StatelessWidget {
  const _Mark({required this.row});
  final HabitRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (row.kind) {
      case RowKind.done:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 18, color: c.onAccent),
        );
      case RowKind.skipped:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: c.sunken,
            shape: BoxShape.circle,
            border: Border.all(color: c.border2),
          ),
          child: Icon(Icons.remove_rounded, size: 16, color: c.muted),
        );
      case RowKind.partial:
        final goal = row.habit.goal ?? 1;
        return ProgressRing(
          value: (row.entry?.value ?? 0) / goal,
          size: 28,
          strokeWidth: 3.5,
          color: c.accent,
          trackColor: c.border,
        );
      default:
        if (row.habit.logType != LogType.tick) {
          return Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.border2, width: 2),
            ),
            child: Icon(logIcon(row.habit.logType), size: 15, color: c.muted),
          );
        }
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.border2, width: 2),
          ),
        );
    }
  }
}

/// One Do habit. A tick habit is finished by tapping the circle; the other
/// kinds open a sheet from the button or the row.
class HabitTile extends StatelessWidget {
  const HabitTile({
    super.key,
    required this.row,
    required this.onToggle,
    required this.onLog,
    required this.onMore,
    this.showDivider = true,
  });

  final HabitRow row;

  /// Tick habits only.
  final VoidCallback onToggle;

  /// Number, note and photo habits: open the entry sheet.
  final VoidCallback onLog;

  /// Long-press or tap on the title: skip, edit, history.
  final VoidCallback onMore;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = row.habit;
    final isTick = h.logType == LogType.tick;
    final finished = row.kind == RowKind.done || row.kind == RowKind.skipped;
    final meta = row.kind == RowKind.skipped
        ? 'Skipped'
        : habitMeta(
            h,
            entry: row.entry,
            lastValue: row.lastValue,
            photoCount: row.photoCount,
          );
    // A stay-clear day set aside has nothing to mark done; the menu counts
    // it again.
    final markable = !h.tracksSlips;
    final markLabel = isTick
        ? (row.kind == RowKind.done
              ? 'Done: ${h.name}. Tap to undo'
              : 'Mark done: ${h.name}')
        : '${h.name}. ${logActionLabel(h)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider ? Border(top: BorderSide(color: c.border)) : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Row(
          children: [
            if (markable)
              Semantics(
                button: true,
                label: markLabel,
                excludeSemantics: true,
                onTap: isTick ? onToggle : onLog,
                child: InkResponse(
                  onTap: isTick ? onToggle : onLog,
                  radius: 28,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(child: _Mark(row: row)),
                  ),
                ),
              )
            else
              SizedBox(
                width: 56,
                height: 56,
                child: Center(child: _Mark(row: row)),
              ),
            Expanded(
              child: InkWell(
                onTap: isTick || !markable ? onMore : onLog,
                onLongPress: onMore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.name,
                        style: AppType.body.copyWith(
                          color: finished ? c.muted : c.ink,
                          decoration: row.kind == RowKind.done
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: c.faint,
                        ),
                      ),
                      Text(
                        meta,
                        style: AppType.caption.copyWith(color: c.faint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (row.streak >= 2 && isTick)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: StreakChip(label: '${row.streak}'),
              ),
            if (!isTick && !finished)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: PillButton(
                  label: logActionLabel(h),
                  icon: logIcon(h.logType),
                  onPressed: onLog,
                  semanticLabel: '${logActionLabel(h)}: ${h.name}',
                ),
              ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// One stay-clear habit: starts on track, with a Slipped button. On a past
/// day the app never saw it is not checked, and asks instead.
class StayClearTile extends StatelessWidget {
  const StayClearTile({
    super.key,
    required this.row,
    required this.onSlip,
    required this.onStayedClear,
    required this.onMore,
    this.showDivider = true,
  });

  final HabitRow row;
  final VoidCallback onSlip;

  /// Unchecked rows only: this habit was on track that day.
  final VoidCallback onStayedClear;
  final VoidCallback onMore;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final slipped = row.kind == RowKind.slipped;
    final unchecked = row.kind == RowKind.unchecked;
    final name = row.habit.name;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider ? Border(top: BorderSide(color: c.border)) : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: c.indigoSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                slipped
                    ? Icons.remove_rounded
                    : unchecked
                    ? Icons.question_mark_rounded
                    : Icons.check_rounded,
                size: 16,
                color: c.indigo,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: onMore,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: AppType.body.copyWith(fontSize: 15),
                          ),
                          if (unchecked)
                            Text(
                              'Not checked',
                              style: AppType.caption.copyWith(color: c.faint),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Under the name: two pills beside it would squeeze it out
                  // on a small phone or at large text.
                  if (unchecked)
                    Padding(
                      padding: const EdgeInsets.only(right: 10, bottom: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PillButton(
                            label: 'I stayed clear',
                            outlined: true,
                            onPressed: onStayedClear,
                            semanticLabel: 'I stayed clear: $name',
                          ),
                          PillButton(
                            label: 'Slipped',
                            outlined: true,
                            onPressed: onSlip,
                            semanticLabel: 'Log a slip: $name',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (row.kind == RowKind.onTrack && row.streak > 0)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 8),
                child: Text(
                  'Day ${row.streak}',
                  style: AppType.caption.copyWith(
                    color: c.indigo,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (!unchecked)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: PillButton(
                  label: slipped ? 'Undo slip' : 'Slipped',
                  outlined: true,
                  onPressed: onSlip,
                  semanticLabel: slipped
                      ? 'Undo the slip: $name'
                      : 'Log a slip: $name',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
