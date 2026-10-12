import 'package:flutter/material.dart';

import '../../core/day_key.dart';
import '../format.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// How one day on the strip is drawn.
class DayDot {
  const DayDot({
    required this.day,
    required this.fraction,
    required this.isFuture,
  });
  final DayKey day;

  /// Share of planned habits done, or null when nothing was planned.
  final double? fraction;
  final bool isFuture;
}

/// Seven days, Monday to Sunday, each with a small ring of how it went.
class DayStrip extends StatelessWidget {
  const DayStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final List<DayDot> days;
  final DayKey selected;
  final DayKey today;
  final ValueChanged<DayKey> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: _Cell(
                dot: d,
                selected: d.day == selected,
                isToday: d.day == today,
                colors: c,
                onTap: d.isFuture ? null : () => onSelect(d.day),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.dot,
    required this.selected,
    required this.isToday,
    required this.colors,
    required this.onTap,
  });
  final DayDot dot;
  final bool selected;
  final bool isToday;
  final AppColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final fg = selected ? c.onAccent : (dot.isFuture ? c.faint : c.ink);
    final pct = dot.fraction == null ? null : (dot.fraction! * 100).round();
    final label =
        '${isToday ? 'Today, ' : ''}${longDate(dot.day)}'
        '${dot.isFuture ? '' : (pct == null ? ', nothing planned' : ', $pct percent done')}';
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekdayLetter(dot.day),
                    style: AppType.caption.copyWith(
                      color: selected ? c.onAccent : c.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ProgressRing(
                    value: dot.fraction ?? 0,
                    size: 36,
                    strokeWidth: 3,
                    color: selected ? c.onAccent : c.accent,
                    trackColor: selected ? c.todayTrack : c.border,
                    child: Text(
                      '${dot.day.day}',
                      style: AppType.small.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
