import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/day_key.dart';
import '../../data/models.dart';
import '../format.dart';
import '../number_input.dart';
import '../theme/tokens.dart';
import '../widgets/keypad.dart';

String _forDay(DayKey day, DayKey today) => day == today
    ? 'Logging for today, ${longDate(day)}'
    : 'Logging for ${shortDate(day)}';

/// Asks for an amount. Returns the amount to save, `0` to clear the day, or
/// null when dismissed.
Future<double?> showNumberSheet(
  BuildContext context, {
  required Habit habit,
  required DayKey day,
  required DayKey today,
  double? current,
  double? lastValue,
}) {
  return showModalBottomSheet<double>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _NumberSheet(
      habit: habit,
      day: day,
      today: today,
      current: current,
      lastValue: lastValue,
    ),
  );
}

class _NumberSheet extends StatefulWidget {
  const _NumberSheet({
    required this.habit,
    required this.day,
    required this.today,
    this.current,
    this.lastValue,
  });
  final Habit habit;
  final DayKey day;
  final DayKey today;
  final double? current;
  final double? lastValue;

  @override
  State<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends State<_NumberSheet> {
  late NumberInput input = NumberInput(
    widget.current == null ? '' : plainAmount(widget.current!),
  );
  late bool _pristine = widget.current != null;

  double get step => stepFor(
    goal: widget.habit.goal,
    lastValue: widget.lastValue,
    current: input.value ?? widget.current,
  );

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_pristine && key != 'back') {
        _pristine = false;
        input = const NumberInput().press(key);
      } else {
        _pristine = false;
        input = input.press(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = widget.habit;
    final unit = h.unit ?? '';
    final value = input.value;
    final canSave = value != null && value > 0;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.name, style: AppType.title),
                      Text(
                        _forDay(widget.day, widget.today),
                        style: AppType.small.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              label: input.text.isEmpty
                  ? 'No amount yet'
                  : '${input.text} $unit',
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        input.text.isEmpty ? '0' : input.text,
                        style: appText(
                          56,
                          800,
                          height: 1.1,
                        ).copyWith(color: input.text.isEmpty ? c.faint : c.ink),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          unit,
                          style: AppType.heading.copyWith(color: c.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (h.goal != null)
              Center(
                child: Text(
                  'Goal ${formatAmountUnit(h.goal!, h.unit)}',
                  style: AppType.small.copyWith(color: c.faint),
                ),
              ),
            if (widget.lastValue != null)
              Center(
                child: Text(
                  'Last time ${formatAmountUnit(widget.lastValue!, h.unit)}',
                  style: AppType.small.copyWith(color: c.faint),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() {
                    _pristine = false;
                    input = input.adjust(-step);
                  }),
                  child: Text('−${formatAmount(step)}'),
                ),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _pristine = false;
                    input = input.adjust(step);
                  }),
                  child: Text('+${formatAmount(step)}'),
                ),
                if (widget.lastValue != null)
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _pristine = true;
                      input = NumberInput(plainAmount(widget.lastValue!));
                    }),
                    child: const Text('Same as last time'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Keypad(
              keys: [
                for (final d in const [
                  '1',
                  '2',
                  '3',
                  '4',
                  '5',
                  '6',
                  '7',
                  '8',
                  '9',
                ])
                  PadKey.digit(d, () => _press(d)),
                PadKey('Decimal point', () => _press('.'), text: '.'),
                PadKey.digit('0', () => _press('0')),
                PadKey.backspace(() => _press('back')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.current != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 0.0),
                      child: const Text('Clear'),
                    ),
                  ),
                Expanded(
                  child: FilledButton(
                    onPressed: canSave
                        ? () => Navigator.pop(context, value)
                        : null,
                    child: Text(
                      canSave
                          ? 'Save ${formatAmountUnit(value, h.unit)}'
                          : 'Save',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a note. Returns the text (empty clears the day) or null when dismissed.
Future<String?> showNoteSheet(
  BuildContext context, {
  required Habit habit,
  required DayKey day,
  required DayKey today,
  String? current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _NoteSheet(habit: habit, day: day, today: today, current: current),
  );
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.habit,
    required this.day,
    required this.today,
    this.current,
  });
  final Habit habit;
  final DayKey day;
  final DayKey today;
  final String? current;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final controller = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.habit.name, style: AppType.title),
            Text(
              _forDay(widget.day, widget.today),
              style: AppType.small.copyWith(color: c.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What happened?'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.current != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, ''),
                      child: const Text('Clear'),
                    ),
                  ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (_, _) => FilledButton(
                      onPressed: controller.text.trim().isEmpty
                          ? null
                          : () => Navigator.pop(context, controller.text),
                      child: const Text('Save note'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum PhotoChoice { camera, gallery, remove }

Future<PhotoChoice?> showPhotoSheet(
  BuildContext context, {
  required Habit habit,
  required bool hasPhoto,
}) {
  return showModalBottomSheet<PhotoChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(habit.name, style: AppType.title),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, PhotoChoice.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, PhotoChoice.gallery),
              ),
              if (hasPhoto)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: ctx.colors.danger,
                  ),
                  title: Text(
                    'Remove this photo',
                    style: TextStyle(color: ctx.colors.danger),
                  ),
                  onTap: () => Navigator.pop(ctx, PhotoChoice.remove),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

enum HabitMenuAction { skip, unskip, edit, details, archive }

/// The long-press menu for a habit on a day.
Future<HabitMenuAction?> showHabitMenu(
  BuildContext context, {
  required Habit habit,
  required bool skipped,
  required bool canSkip,
}) {
  return showModalBottomSheet<HabitMenuAction>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(habit.name, style: AppType.title),
                ),
              ),
              if (canSkip)
                ListTile(
                  leading: Icon(
                    skipped ? Icons.undo_rounded : Icons.event_busy_outlined,
                  ),
                  title: Text(
                    skipped ? 'Count this day again' : 'Skip this day',
                  ),
                  subtitle: skipped
                      ? null
                      : const Text(
                          'Left out of your rate. Your streak is kept.',
                        ),
                  onTap: () => Navigator.pop(
                    ctx,
                    skipped ? HabitMenuAction.unskip : HabitMenuAction.skip,
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.show_chart_rounded),
                title: const Text('History'),
                onTap: () => Navigator.pop(ctx, HabitMenuAction.details),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit habit'),
                onTap: () => Navigator.pop(ctx, HabitMenuAction.edit),
              ),
              if (!habit.isArchived)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Archive'),
                  subtitle: const Text(
                    'Hides it from today on. History is kept.',
                  ),
                  onTap: () => Navigator.pop(ctx, HabitMenuAction.archive),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
