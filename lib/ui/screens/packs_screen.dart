import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/packs.dart';
import '../../logic/habit_form.dart';
import '../../services/files.dart';
import '../../state/providers.dart';
import '../../state/lock_controller.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Starter packs and pack files. [openId] opens a pack's preview straight away; [import] starts the file picker.
class PacksScreen extends ConsumerStatefulWidget {
  const PacksScreen({super.key, this.openId, this.import = false});
  final String? openId;
  final bool import;

  @override
  ConsumerState<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends ConsumerState<PacksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.import) {
        unawaited(_import());
      } else if (widget.openId != null) {
        final p = starterPacks.where((p) => p.id == widget.openId).firstOrNull;
        if (p != null) unawaited(_preview(p));
      }
    });
  }

  Future<void> _import() async {
    try {
      final text = await ref
          .read(lockedProvider.notifier)
          .runExternal(() => ref.read(fileServiceProvider).pickAndReadText());
      if (text == null || !mounted) return;
      await _preview(decodePack(text));
    } on FormatException catch (e) {
      if (mounted) _say(e.message);
    } catch (e) {
      if (mounted) _say('Could not read that file.');
    }
  }

  void _say(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _preview(StarterPack pack) async {
    final existing = ref.read(ledgerProvider).value?.habits ?? const <Habit>[];
    final plan = planPackApply(existing, pack);
    final go = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _PackSheet(pack: pack, plan: plan),
    );
    if (go != true || !mounted) return;
    final actions = ref.read(actionsProvider);
    final today = ref.read(todayProvider);
    try {
      for (final f in plan.toAdd) {
        await actions.addHabit(
          f.toHabit(Habit(id: '', name: 'x', createdDay: today)),
          today: today,
        );
      }
    } catch (_) {
      if (mounted)
        _say('Could not add all of them. Check Habits and try again.');
      return;
    }
    if (!mounted) return;
    final skipped = plan.skipped.length;
    _say(
      'Added ${plural(plan.toAdd.length, 'habit')}${skipped > 0 ? '. Skipped $skipped you already have.' : '.'}',
    );
    context.go('/habits');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Starter packs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            'Pick a set to start with. You can change or remove anything afterwards.',
            style: AppType.bodyLight.copyWith(color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          for (final p in starterPacks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                child: InkWell(
                  onTap: () => _preview(p),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: AppType.heading),
                        const SizedBox(height: 2),
                        Text(
                          p.description,
                          style: AppType.small.copyWith(color: c.muted),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          plural(p.habits.length, 'habit'),
                          style: AppType.caption.copyWith(
                            color: c.accentInk,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import a pack from a file'),
          ),
        ],
      ),
    );
  }
}

class _PackSheet extends StatelessWidget {
  const _PackSheet({required this.pack, required this.plan});
  final StarterPack pack;
  final PackPlan plan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(pack.name, style: AppType.title),
            if (pack.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  pack.description,
                  style: AppType.small.copyWith(color: c.muted),
                ),
              ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in plan.toAdd) _line(c, f, false),
                  for (final name in plan.skipped)
                    _line(c, HabitForm(name: name), true),
                ],
              ),
            ),
            if (plan.skipped.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${plural(plan.skipped.length, 'habit')} you already have will be skipped.',
                  style: AppType.small.copyWith(color: c.muted),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: plan.toAdd.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(
                plan.toAdd.isEmpty
                    ? 'You have all of these'
                    : 'Add ${plural(plan.toAdd.length, 'habit')}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(AppColors c, HabitForm f, bool skipped) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(
          skipped
              ? Icons.check_rounded
              : (f.kind == HabitKind.avoid
                    ? Icons.block_flipped
                    : Icons.add_rounded),
          size: 18,
          color: skipped
              ? c.faint
              : (f.kind == HabitKind.avoid ? c.indigo : c.accentInk),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            f.name,
            style: AppType.bodyLight.copyWith(
              color: skipped ? c.faint : c.ink,
              decoration: skipped ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (f.kind == HabitKind.avoid && !skipped)
          Text('stay clear', style: AppType.caption.copyWith(color: c.indigo)),
      ],
    ),
  );
}
