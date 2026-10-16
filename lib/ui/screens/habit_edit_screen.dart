import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models.dart';
import '../../logic/habit_form.dart';
import '../../state/providers.dart';
import '../../state/lock_controller.dart';
import '../commands.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

const _suggestedAreas = ['Health', 'Mind', 'Work', 'Home', 'Money', 'People'];

/// Add a habit, or edit one when [habitId] is given. [preset] fills a new habit (starter packs).
class HabitEditScreen extends ConsumerStatefulWidget {
  const HabitEditScreen({super.key, this.habitId, this.preset});
  final String? habitId;
  final HabitForm? preset;

  @override
  ConsumerState<HabitEditScreen> createState() => _HabitEditScreenState();
}

class _HabitEditScreenState extends ConsumerState<HabitEditScreen>
    with WidgetsBindingObserver {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _unit = TextEditingController();
  final _goal = TextEditingController();
  final _area = TextEditingController();

  // Where each error is drawn, to bring the first one into view on Save.
  final _nameKey = GlobalKey();
  final _numberKey = GlobalKey();
  final _daysKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _descriptionKey = GlobalKey();

  HabitForm _form = const HabitForm();
  Habit? _original;
  bool _loaded = false;
  bool _dirty = false;
  bool _showErrors = false;
  bool _saving = false;
  bool _notificationsBlocked = false;

  /// "Pick days" is chosen. Kept apart from the mask, so picking all seven
  /// days or Monday to Friday does not take the picker away.
  bool _customDays = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshNotificationPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_name, _description, _unit, _goal, _area]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshNotificationPermission());
    }
  }

  Future<void> _refreshNotificationPermission() async {
    try {
      final allowed = await ref.read(reminderSchedulerProvider).hasPermission();
      if (mounted && _notificationsBlocked == allowed) {
        setState(() => _notificationsBlocked = !allowed);
      }
    } catch (_) {}
  }

  void _load(HabitForm f, Habit? original) {
    _original = original;
    _form = f;
    _name.text = f.name;
    _description.text = f.description;
    _unit.text = f.unit;
    _goal.text = f.goalText;
    _area.text = f.area;
    _customDays =
        f.daysMask != Habit.everyDay && f.daysMask != Habit.weekdaysOnly;
    _loaded = true;
  }

  void _change(HabitForm Function(HabitForm) edit) => setState(() {
    _form = edit(_form);
    _dirty = true;
  });

  Future<void> _pickTime() async {
    final current = _form.reminderMinutes ?? 8 * 60;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t != null && mounted)
      _change((f) => f.copyWith(reminderMinutes: () => t.hour * 60 + t.minute));
  }

  Future<void> _toggleReminder(bool on) async {
    if (!on) return _change((f) => f.copyWith(reminderMinutes: () => null));
    final granted = await ref
        .read(lockedProvider.notifier)
        .runExternal(
          () => ref.read(reminderSchedulerProvider).requestPermission(),
        );
    if (!mounted) return;
    setState(() => _notificationsBlocked = !granted);
    _change(
      (f) => f.copyWith(reminderMinutes: () => _form.reminderMinutes ?? 8 * 60),
    );
  }

  void _popOrHome({String? deletedId}) {
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      context.pop();
      if (deletedId != null && mounted && Navigator.canPop(context)) {
        try {
          final uri = GoRouter.of(context).state.uri.path;
          if (uri == '/habit/${Uri.encodeComponent(deletedId)}' ||
              uri == '/habit/$deletedId') {
            context.pop();
          }
        } catch (_) {}
      }
    } else {
      context.go('/');
    }
  }

  /// The first error may be off screen: scroll to it, and say so.
  void _showFirstError() {
    final f = _form;
    final key = [
      (f.nameError, _nameKey),
      (f.unitError ?? f.goalError, _numberKey),
      (f.daysError, _daysKey),
      (f.areaError, _areaKey),
      (f.descriptionError, _descriptionKey),
    ].firstWhere((e) => e.$1 != null).$2;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    // After this frame, which draws the error text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target != null && target.mounted) {
        unawaited(Scrollable.ensureVisible(target, duration: duration));
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Check the fields marked in red.')),
      );
  }

  Future<void> _save() async {
    setState(() => _showErrors = true);
    if (_saving) return;
    if (!_form.isValid) return _showFirstError();
    setState(() => _saving = true);
    final actions = ref.read(actionsProvider);
    try {
      if (_original == null) {
        await actions.addHabit(
          _form.toHabit(
            Habit(id: '', name: 'x', createdDay: ref.read(todayProvider)),
          ),
          today: ref.read(todayProvider),
        );
      } else {
        await actions.updateHabit(_form.toHabit(_original!));
      }
      _dirty = false;
      _popOrHome();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That did not save. Try again.')),
        );
      }
      debugPrint('Saving a habit failed: $e');
    }
  }

  Future<void> _archiveHabit() async {
    if (_saving || _original == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(actionsProvider)
          .archive(_original!, ref.read(todayProvider));
      _dirty = false;
      _popOrHome();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That did not save. Try again.')),
        );
      }
    }
  }

  Future<void> _deleteHabit() async {
    if (_saving || _original == null) return;
    setState(() => _saving = true);
    try {
      if (await confirmAndDeleteHabit(context, ref, _original!)) {
        _dirty = false;
        _popOrHome(deletedId: _original!.id);
      } else if (mounted) {
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That did not save. Try again.')),
        );
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'What you changed on this screen has not been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    if (widget.habitId != null) {
      final habits = ledger.value?.habits;
      if (habits == null) {
        if (!_loaded) {
          if (ledger.hasError) {
            return Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load this habit',
                action: FilledButton(
                  onPressed: () => ref.invalidate(ledgerProvider),
                  child: const Text('Try again'),
                ),
              ),
            );
          }
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
      } else {
        final h = habits.where((x) => x.id == widget.habitId).firstOrNull;
        if (h == null && !_saving) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'This habit no longer exists',
            ),
          );
        }
        if (h != null) {
          if (!_loaded || (!_dirty && h != _original)) {
            _load(HabitForm.fromHabit(h), h);
          } else {
            _original = h;
          }
        }
      }
    } else if (!_loaded) {
      _load(widget.preset ?? const HabitForm(), null);
    }
    final c = context.colors;
    final f = _form;
    final editing = _original != null;
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    // A 2.0.2 area can be over the limit, and picking it would be refused.
    final areas = {
      ..._suggestedAreas,
      for (final h in ledger.value?.habits ?? const <Habit>[])
        if (h.area != null && h.area!.trim().length <= HabitForm.maxAreaLength)
          h.area!,
    }.toList();

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _dirty = false);
          _popOrHome();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'Edit habit' : 'New habit'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            onPressed: () async {
              if (!_dirty || await _confirmDiscard()) {
                _dirty = false;
                _popOrHome();
              }
            },
          ),
          actions: [
            if (!editing)
              TextButton(
                onPressed: () async {
                  if (!_dirty || await _confirmDiscard()) {
                    _dirty = false;
                    if (context.mounted) {
                      context.pushReplacement('/habits/packs');
                    }
                  }
                },
                child: const Text('Starter packs'),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              // Not a lazy list: a field in error must exist to be scrolled to.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: _nameKey,
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      maxLength: HabitForm.maxNameLength + 20,
                      buildCounter: (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                      style: AppType.heading,
                      decoration: InputDecoration(
                        hintText: 'Name, e.g. Drink water',
                        errorText: _showErrors ? f.nameError : null,
                      ),
                      onChanged: (v) => _change((x) => x.copyWith(name: v)),
                    ),
                    const _Label('I want to'),
                    _Options<HabitKind>(
                      value: f.kind,
                      options: const {
                        HabitKind.build: 'Do this',
                        HabitKind.avoid: 'Avoid this',
                      },
                      onChanged: (v) => _change((x) => x.copyWith(kind: v)),
                    ),
                    if (f.kind == HabitKind.avoid) ...[
                      const _Label('How do you want to track it?'),
                      _Options<AvoidMode>(
                        value: f.avoidMode,
                        options: const {
                          AvoidMode.track: 'Log slips only',
                          AvoidMode.confirm: 'Tick it each day',
                        },
                        onChanged: (v) =>
                            _change((x) => x.copyWith(avoidMode: v)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          f.avoidMode == AvoidMode.track
                              ? 'Every day starts on track. You only tap Slipped when it happens, and an evening check-in asks how the day went.'
                              : 'You tick it each day to confirm you stayed clear. A day you do not tick counts as missed.',
                          style: AppType.small.copyWith(
                            color: c.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    if (!f.logsSlips) ...[
                      const _Label('How do you log it?'),
                      _Options<LogType>(
                        value: f.logType,
                        options: const {
                          LogType.tick: 'Tick',
                          LogType.number: 'Number',
                          LogType.note: 'Note',
                          LogType.photo: 'Photo',
                        },
                        onChanged: (v) =>
                            _change((x) => x.copyWith(logType: v)),
                      ),
                      if (f.logType == LogType.number)
                        Padding(
                          key: _numberKey,
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _unit,
                                  decoration: InputDecoration(
                                    labelText: 'Unit',
                                    hintText: 'glasses',
                                    errorText: _showErrors ? f.unitError : null,
                                  ),
                                  onChanged: (v) =>
                                      _change((x) => x.copyWith(unit: v)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _goal,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Daily goal',
                                    hintText: 'optional',
                                    errorText: _showErrors ? f.goalError : null,
                                  ),
                                  onChanged: (v) =>
                                      _change((x) => x.copyWith(goalText: v)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (!f.logsSlips) ...[
                      const _Label('Repeats'),
                      _Options<int>(
                        key: _daysKey,
                        value: _customDays ? -1 : f.daysMask,
                        options: const {
                          Habit.everyDay: 'Every day',
                          Habit.weekdaysOnly: 'Weekdays',
                          -1: 'Pick days',
                        },
                        onChanged: (v) => _change((x) {
                          _customDays = v == -1;
                          // The picker starts from the days already chosen.
                          return _customDays ? x : x.copyWith(daysMask: v);
                        }),
                      ),
                      if (_customDays)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _DayPicker(
                            mask: f.daysMask,
                            onChanged: (m) =>
                                _change((x) => x.copyWith(daysMask: m)),
                          ),
                        ),
                      if (_showErrors && f.daysError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            f.daysError!,
                            style: AppType.small.copyWith(color: c.danger),
                          ),
                        ),
                    ],
                    if (editing)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Changing the days, or how you track it, applies to earlier days too, so past streaks can change.',
                          style: AppType.small.copyWith(
                            color: c.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    const _Label('Time of day'),
                    _Options<DayPart>(
                      value: f.dayPart,
                      options: {
                        for (final p in DayPart.values) p: dayPartName(p),
                      },
                      onChanged: (v) => _change((x) => x.copyWith(dayPart: v)),
                    ),
                    if (!f.logsSlips) ...[
                      const SizedBox(height: 20),
                      SurfaceCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            // The card paints a background; ink needs its own Material above it.
                            Material(
                              type: MaterialType.transparency,
                              child: SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  f.reminderMinutes == null
                                      ? 'Remind me'
                                      : 'Remind me at ${formatMinutes(f.reminderMinutes!, use24h: use24h)}',
                                  style: AppType.body,
                                ),
                                subtitle: Text(
                                  f.reminderMinutes == null
                                      ? 'A notification at a time you pick.'
                                      : 'On the days it repeats. Quiet hours are respected.',
                                  style: AppType.small.copyWith(color: c.muted),
                                ),
                                value: f.reminderMinutes != null,
                                onChanged: _toggleReminder,
                              ),
                            ),
                            if (f.reminderMinutes != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _pickTime,
                                  icon: const Icon(Icons.schedule_rounded),
                                  label: const Text('Change time'),
                                ),
                              ),
                            if (_notificationsBlocked &&
                                f.reminderMinutes != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.notifications_off_outlined,
                                      size: 18,
                                      color: c.amberInk,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Notifications are off for this app, so this reminder will not show.',
                                        style: AppType.small.copyWith(
                                          color: c.amberInk,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => ref
                                          .read(lockedProvider.notifier)
                                          .runExternal(
                                            openAppSettings,
                                            opensActivity: true,
                                          ),
                                      child: const Text('Open settings'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const _Label('Area (optional)'),
                    TextField(
                      key: _areaKey,
                      controller: _area,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Health, Mind, Work...',
                        errorText: _showErrors ? f.areaError : null,
                      ),
                      onChanged: (v) => _change((x) => x.copyWith(area: v)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final a in areas)
                          ActionChip(
                            label: Text(a),
                            onPressed: () {
                              _area.text = a;
                              _change((x) => x.copyWith(area: a));
                            },
                          ),
                      ],
                    ),
                    const _Label('Note to self (optional)'),
                    TextField(
                      key: _descriptionKey,
                      controller: _description,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Why this matters, or what counts',
                        errorText: _showErrors ? f.descriptionError : null,
                      ),
                      onChanged: (v) =>
                          _change((x) => x.copyWith(description: v)),
                    ),
                    if (editing) ...[
                      const SizedBox(height: 28),
                      if (!_original!.isArchived) ...[
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _archiveHabit,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Archive, keep history'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        onPressed: _saving ? null : _deleteHabit,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete habit and history'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(editing ? 'Save changes' : 'Add habit'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: AppType.overline.copyWith(color: context.colors.muted),
      ),
    ),
  );
}

/// A row of mutually exclusive choices, drawn as bordered chips.
class _Options<T> extends StatelessWidget {
  const _Options({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          Semantics(
            button: true,
            selected: e.key == value,
            label: e.value,
            onTap: () => onChanged(e.key),
            excludeSemantics: true,
            child: Material(
              color: e.key == value ? c.accentSoft : c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: e.key == value ? c.accent : c.border2,
                  width: e.key == value ? 2 : 1,
                ),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onTap: () => onChanged(e.key),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    minWidth: 64,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        e.value,
                        style: AppType.button.copyWith(
                          color: e.key == value ? c.accentInk : c.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.mask, required this.onChanged});
  final int mask;
  final ValueChanged<int> onChanged;

  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: (mask >> i) & 1 == 1,
                label: _names[i],
                onTap: () => onChanged(mask ^ (1 << i)),
                excludeSemantics: true,
                child: Material(
                  color: (mask >> i) & 1 == 1 ? c.accent : c.surface,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: (mask >> i) & 1 == 1 ? c.accent : c.border2,
                    ),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onChanged(mask ^ (1 << i)),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          _letters[i],
                          style: AppType.button.copyWith(
                            color: (mask >> i) & 1 == 1 ? c.onAccent : c.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
