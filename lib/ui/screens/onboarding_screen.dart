import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/packs.dart';
import '../../logic/habit_form.dart';
import '../../services/reminder_sync.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../theme/tokens.dart';

/// First run: pick a few habits, then decide about notifications.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _picked = <String>{};
  int _step = 0;
  bool _busy = false;

  Future<void> _finish({required bool allowNotifications}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (allowNotifications)
        await ref.read(reminderSchedulerProvider).requestPermission();
      final today = ref.read(todayProvider);
      final actions = ref.read(actionsProvider);
      for (final f in [...onboardingDo, ...onboardingAvoid]) {
        if (_picked.contains(f.name)) {
          await actions.addHabit(
            f.toHabit(Habit(id: '', name: 'x', createdDay: today)),
            today: today,
          );
        }
      }
      await ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(onboardingDone: true));
      unawaited(ref.read(reminderSyncProvider).resync());
      if (mounted) context.go('/');
    } catch (e) {
      debugPrint('Finishing the first-run screen failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That did not save. Try again.')),
        );
      }
    }
  }

  Future<void> _skip() async {
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(onboardingDone: true));
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: TextButton(
                  onPressed: _busy ? null : _skip,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                child: _step == 0 ? _picker(context) : _notifications(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  if (_step == 0) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _step = 1),
                        child: Text(
                          _picked.isEmpty
                              ? 'Start empty'
                              : 'Start with ${plural(_picked.length, 'habit')}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Next: decide about notifications. They are optional.',
                      style: AppType.small.copyWith(color: c.muted),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _finish(allowNotifications: true),
                        child: const Text('Allow notifications'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _finish(allowNotifications: false),
                      child: const Text('Not now'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _picker(BuildContext context) {
    final c = context.colors;
    Widget chips(List<HabitForm> list, {required bool avoid}) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in list)
          FilterChip(
            label: Text(f.name),
            selected: _picked.contains(f.name),
            showCheckmark: true,
            selectedColor: avoid ? c.indigoSoft : c.accentSoft,
            checkmarkColor: avoid ? c.indigo : c.accentInk,
            onSelected: (v) => setState(
              () => v ? _picked.add(f.name) : _picked.remove(f.name),
            ),
          ),
      ],
    );
    return ListView(
      key: const ValueKey('picker'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      children: [
        Semantics(
          header: true,
          child: Text('What will you do every day?', style: AppType.display),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a few to start. You can change all of it later.',
          style: AppType.bodyLight.copyWith(color: c.muted),
        ),
        const SizedBox(height: 24),
        Text('DO', style: AppType.overline.copyWith(color: c.muted)),
        const SizedBox(height: 8),
        chips(onboardingDo, avoid: false),
        const SizedBox(height: 24),
        Text('STAY CLEAR OF', style: AppType.overline.copyWith(color: c.muted)),
        const SizedBox(height: 4),
        Text(
          'Each day starts on track. You only log it if you slip.',
          style: AppType.small.copyWith(color: c.muted),
        ),
        const SizedBox(height: 8),
        chips(onboardingAvoid, avoid: true),
      ],
    );
  }

  Widget _notifications(BuildContext context) {
    final c = context.colors;
    return ListView(
      key: const ValueKey('notifications'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.notifications_active_outlined,
            color: c.accentInk,
            size: 34,
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text('Want a nudge?', style: AppType.display),
        ),
        const SizedBox(height: 8),
        Text(
          'Notifications let a habit remind you at the time you choose, and ask in the evening how the day went. You set a time on each habit, and quiet hours keep the night free.',
          style: AppType.bodyLight.copyWith(color: c.muted, height: 1.45),
        ),
      ],
    );
  }
}
