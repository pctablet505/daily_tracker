import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/tokens.dart';

/// The three tabs with an add button at the end of the bar.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Material(
        color: c.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  _Tab(
                    icon: Icons.task_alt_rounded,
                    label: 'Today',
                    index: 0,
                    shell: navigationShell,
                  ),
                  _Tab(
                    icon: Icons.bar_chart_rounded,
                    label: 'Progress',
                    index: 1,
                    shell: navigationShell,
                  ),
                  _Tab(
                    icon: Icons.list_rounded,
                    label: 'Habits',
                    index: 2,
                    shell: navigationShell,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 12),
                    child: Semantics(
                      button: true,
                      label: 'Add a habit',
                      excludeSemantics: true,
                      child: Material(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => context.push('/habit/new'),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: Icon(
                              Icons.add_rounded,
                              size: 28,
                              color: c.onAccent,
                            ),
                          ),
                        ),
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

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.index,
    required this.shell,
  });
  final IconData icon;
  final String label;
  final int index;
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = shell.currentIndex == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: () => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? c.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? c.accentInk : c.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppType.caption.copyWith(
                  color: selected ? c.ink : c.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
