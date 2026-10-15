import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/packs.dart';
import '../../state/providers.dart';
import '../commands.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/habit_tiles.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  bool _archived = false;
  final _restarting = <String>{};
  String? _area;

  String _sub(Habit h, bool use24h) {
    final parts = <String>[];
    if (h.tracksSlips) {
      parts.add('Staying clear');
    } else {
      parts.add(scheduleSummary(h.daysMask));
      parts.add(dayPartName(h.dayPart));
      if (h.kind == HabitKind.avoid) parts.add('tick each day');
    }
    if (h.reminderMinutes != null)
      parts.add(
        'reminder ${formatMinutes(h.reminderMinutes!, use24h: use24h)}',
      );
    return parts.join(' · ');
  }

  /// Runs a write the list started; a failure is said, not lost.
  Future<void> _guard(Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      debugPrint('Habits action failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That did not save. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ledger = ref.watch(ledgerProvider);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Habits', style: AppType.display),
                  ),
                ),
                const SettingsButton(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Active')),
                ButtonSegment(value: true, label: Text('Archived')),
              ],
              selected: {_archived},
              onSelectionChanged: (s) => setState(() {
                _archived = s.first;
                _area = null;
              }),
            ),
          ),
          Expanded(
            // A write reloads the ledger; keep the list as it was meanwhile.
            child: ledger.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load your habits',
                action: FilledButton(
                  onPressed: () => ref.invalidate(ledgerProvider),
                  child: const Text('Try again'),
                ),
              ),
              data: (l) {
                final active = l.habits.where((h) => !h.isArchived).toList();
                final archived = l.habits.where((h) => h.isArchived).toList()
                  ..sort((a, b) => b.endDay!.compareTo(a.endDay!));
                if (_archived) return _archivedList(archived, active, use24h);
                return _activeList(active, use24h, c);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeList(List<Habit> active, bool use24h, AppColors c) {
    final areas = {
      for (final h in active)
        if (h.area != null) h.area!,
    }.toList()..sort();
    final selectedArea = areas.contains(_area) ? _area : null;
    final shown = selectedArea == null
        ? active
        : active.where((h) => h.area == selectedArea).toList();
    const padding = EdgeInsets.fromLTRB(20, 4, 20, 24);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          'Starter packs',
          padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
        ),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(124),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in starterPacks)
                _PackCard(
                  pack: p,
                  onTap: () => context.push('/habits/packs?open=${p.id}'),
                ),
              _PackCard(
                title: 'Import a pack',
                subtitle: 'from a file',
                icon: Icons.file_open_outlined,
                onTap: () => context.push('/habits/packs?import=1'),
              ),
            ],
          ),
        ),
        SectionHeader(
          'Active, ${active.length}',
          trailing: active.length > 1 && selectedArea == null
              ? 'hold the handle to reorder'
              : null,
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
        ),
        if (areas.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: selectedArea == null,
                  onSelected: (_) => setState(() => _area = null),
                ),
                for (final a in areas)
                  FilterChip(
                    label: Text(
                      a,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: selectedArea == a,
                    onSelected: (_) =>
                        setState(() => _area = selectedArea == a ? null : a),
                  ),
              ],
            ),
          ),
        if (active.isEmpty)
          EmptyState(
            icon: Icons.spa_outlined,
            title: 'No habits yet',
            message:
                'Pick a starter pack above, or add your own with the + button.',
            action: FilledButton(
              onPressed: () => context.push('/habit/new'),
              child: const Text('Add a habit'),
            ),
          ),
      ],
    );
    Widget item(BuildContext context, int i) {
      final h = shown[i];
      return Padding(
        key: ValueKey(h.id),
        padding: const EdgeInsets.only(bottom: 8),
        child: SurfaceCard(
          radius: 16,
          child: InkWell(
            onTap: () => context.push('/habit/${Uri.encodeComponent(h.id)}'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(
                    h.kind == HabitKind.avoid
                        ? Icons.block_flipped
                        : (h.logType == LogType.tick
                              ? Icons.task_alt_rounded
                              : logIcon(h.logType)),
                    size: 22,
                    color: h.kind == HabitKind.avoid ? c.indigo : c.accentInk,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.name, style: AppType.body),
                          Text(
                            _sub(h, use24h),
                            style: AppType.caption.copyWith(color: c.faint),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selectedArea == null && active.length > 1)
                    ReorderableDragStartListener(
                      index: i,
                      child: Semantics(
                        label: 'Reorder ${h.name}',
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.drag_indicator_rounded),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // A filtered list cannot be reordered: a move inside it has no clear
    // place in the full order.
    if (selectedArea != null) {
      return ListView.builder(
        padding: padding,
        itemCount: shown.length + 1,
        itemBuilder: (context, i) => i == 0 ? header : item(context, i - 1),
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: padding,
      header: header,
      itemCount: shown.length,
      onReorderItem: (from, to) {
        final ids = [for (final h in shown) h.id];
        ids.insert(to, ids.removeAt(from));
        _guard(
          () => ref.read(actionsProvider).reorder(ids, [
            for (final h in active) h.id,
          ]),
        );
      },
      itemBuilder: item,
    );
  }

  Widget _archivedList(List<Habit> archived, List<Habit> active, bool use24h) {
    final c = context.colors;
    if (archived.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Nothing archived',
        message: 'Archive a habit you are done with. Its history stays, and it leaves your lists.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        for (final h in archived)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SurfaceCard(
              radius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () =>
                        context.push('/habit/${Uri.encodeComponent(h.id)}'),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.name, style: AppType.body),
                          Text(
                            'Ended ${shortDate(h.endDay! < h.createdDay ? h.createdDay : h.endDay!)}',
                            style: AppType.caption.copyWith(color: c.faint),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: Wrap(
                      children: [
                        TextButton(
                          onPressed: () async {
                            if (!_restarting.add(h.id)) return;
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final alreadyActive = active.any(
                                (x) =>
                                    x.name.trim().toLowerCase() ==
                                    h.name.trim().toLowerCase(),
                              );
                              if (alreadyActive) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'You already have an active ${h.name}.',
                                    ),
                                  ),
                                );
                                if (mounted) setState(() => _archived = false);
                                return;
                              }
                              final fresh = await ref
                                  .read(actionsProvider)
                                  .startAgain(h, ref.read(todayProvider));
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Started ${fresh.name} again from today',
                                  ),
                                ),
                              );
                              if (mounted) setState(() => _archived = false);
                            } catch (e) {
                              debugPrint('Restarting habit failed: $e');
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'That did not save. Try again.',
                                  ),
                                ),
                              );
                            } finally {
                              _restarting.remove(h.id);
                            }
                          },
                          child: const Text('Start again'),
                        ),
                        TextButton(
                          onPressed: () => _guard(
                            () => confirmAndDeleteHabit(context, ref, h),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: c.danger,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    this.pack,
    this.title,
    this.subtitle,
    this.icon = Icons.auto_awesome_outlined,
    required this.onTap,
  });
  final StarterPack? pack;
  final String? title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = pack?.name ?? title!;
    final sub = pack != null ? '${pack!.habits.length} habits' : subtitle!;
    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 4),
      child: SizedBox(
        width: 148,
        child: SurfaceCard(
          radius: 18,
          color: c.accentSoft,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: c.accentInk),
                  const Spacer(),
                  Text(
                    name,
                    style: AppType.body.copyWith(
                      color: c.accentInk,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sub,
                    style: AppType.caption.copyWith(color: c.accentInk),
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
