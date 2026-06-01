import 'package:flutter/material.dart';

class PinDots extends StatelessWidget {
  final int pinLength;
  final int maxLength;
  final double dotSize;
  final double spacing;

  const PinDots({
    super.key,
    required this.pinLength,
    this.maxLength = 4,
    this.dotSize = 20,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxLength, (index) {
        final filled = index < pinLength;
        return Container(
          width: dotSize,
          height: dotSize,
          margin: EdgeInsets.symmetric(horizontal: spacing),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
          ),
        );
      }),
    );
  }
}

class NumpadGrid extends StatelessWidget {
  final VoidCallback? onBackspace;
  final ValueChanged<String> onDigitPressed;
  final double buttonSize;
  final double textSize;

  const NumpadGrid({
    super.key,
    this.onBackspace,
    required this.onDigitPressed,
    this.buttonSize = 72,
    this.textSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildRow(['1', '2', '3'], colorScheme),
        const SizedBox(height: 16),
        _buildRow(['4', '5', '6'], colorScheme),
        const SizedBox(height: 16),
        _buildRow(['7', '8', '9'], colorScheme),
        const SizedBox(height: 16),
        _buildRow(['', '0', 'backspace'], colorScheme),
      ],
    );
  }

  Widget _buildRow(List<String> keys, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key == 'backspace') {
          return _NumpadButton(
            size: buttonSize,
            onPressed: onBackspace,
            child: Icon(Icons.backspace_outlined, color: colorScheme.onSurface),
          );
        }
        if (key.isEmpty) {
          return SizedBox(width: buttonSize, height: buttonSize);
        }
        return _NumpadButton(
          size: buttonSize,
          onPressed: () => onDigitPressed(key),
          child: Text(
            key,
            style: TextStyle(
              fontSize: textSize,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NumpadButton extends StatelessWidget {
  final double size;
  final VoidCallback? onPressed;
  final Widget child;

  const _NumpadButton({
    required this.size,
    this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: Center(child: child),
      ),
    );
  }
}
