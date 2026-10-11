import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One key of a [Keypad]: a digit or symbol, or the accent-coloured main action.
class PadKey {
  const PadKey(
    this.semantics,
    this.onTap, {
    this.text,
    this.icon,
    this.primary = false,
  });

  PadKey.digit(String digit, VoidCallback? onTap)
    : this('Digit $digit', onTap, text: digit);

  PadKey.backspace(VoidCallback? onTap)
    : this('Delete last digit', onTap, icon: Icons.backspace_outlined);

  final String semantics;

  /// Null greys the key out.
  final VoidCallback? onTap;
  final String? text;
  final IconData? icon;
  final bool primary;
}

/// A three-column pad of large keys, used for PINs and for typing a number.
class Keypad extends StatelessWidget {
  const Keypad({super.key, required this.keys, this.aspectRatio = 2.4});
  final List<PadKey> keys;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: aspectRatio,
      children: [
        for (final k in keys)
          Semantics(
            button: true,
            enabled: k.onTap != null,
            label: k.semantics,
            excludeSemantics: true,
            child: Material(
              color: !k.primary
                  ? c.sunken
                  : (k.onTap != null ? c.accent : c.sunken),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: k.onTap,
                child: Center(
                  child: k.icon != null
                      ? Icon(
                          k.icon,
                          color: !k.primary
                              ? c.ink
                              : (k.onTap != null ? c.onAccent : c.faint),
                        )
                      : Text(k.text!, style: appText(24, 700, color: c.ink)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
