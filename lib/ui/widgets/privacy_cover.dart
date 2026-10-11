import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Covers [child] with a plain screen whenever the app is not in the
/// foreground, so Android's recent-apps preview shows nothing of the habits.
/// Only active when [enabled] (the app lock is on).
class PrivacyCover extends StatefulWidget {
  const PrivacyCover({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover>
    with WidgetsBindingObserver {
  bool _away = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away != _away) setState(() => _away = away);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.enabled && _away)
          Positioned.fill(
            child: ColoredBox(
              key: const ValueKey('privacy-cover'),
              color: c.bg,
              child: Center(
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.task_alt_rounded,
                    size: 72,
                    color: c.accent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
