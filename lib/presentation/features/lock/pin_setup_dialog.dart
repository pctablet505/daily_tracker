import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../widgets/common/numpad_grid.dart';

class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PinSetupDialog(),
    );
    return result ?? false;
  }

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  String _errorMessage = '';

  void _onDigitPressed(String digit) {
    final currentPin = _isConfirming ? _confirmPin : _pin;
    if (currentPin.length >= 4) return;

    setState(() {
      _errorMessage = '';
      if (_isConfirming) {
        _confirmPin += digit;
      } else {
        _pin += digit;
      }
    });

    final updatedPin = _isConfirming ? _confirmPin : _pin;
    if (updatedPin.length == 4 && !_isConfirming) {
      setState(() => _isConfirming = true);
    } else if (_confirmPin.length == 4) {
      _savePin();
    }
  }

  void _onBackspace() {
    setState(() {
      _errorMessage = '';
      if (_isConfirming && _confirmPin.isNotEmpty) {
        _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      } else if (!_isConfirming && _pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  Future<void> _savePin() async {
    if (_pin != _confirmPin) {
      setState(() {
        _errorMessage = 'PINs do not match. Try again.';
        _pin = '';
        _confirmPin = '';
        _isConfirming = false;
      });
      HapticFeedback.mediumImpact();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hashedPin = CryptoUtils.hashPin(_pin);
    await prefs.setString(AppConstants.prefAppLockPin, hashedPin);

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentPin = _isConfirming ? _confirmPin : _pin;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isConfirming ? 'Confirm PIN' : 'Set PIN',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isConfirming
                  ? 'Enter the same PIN again'
                  : 'Create a 4-digit PIN',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            PinDots(
              pinLength: currentPin.length,
              dotSize: 16,
              spacing: 8,
            ),
            const SizedBox(height: 12),
            if (_errorMessage.isNotEmpty)
              Text(
                _errorMessage,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.error),
              ),
            const SizedBox(height: 16),
            NumpadGrid(
              onDigitPressed: _onDigitPressed,
              onBackspace: _onBackspace,
              buttonSize: 56,
              textSize: 24,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
