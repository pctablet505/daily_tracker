import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../widgets/common/numpad_grid.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const AppLockScreen({super.key, required this.onUnlock});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _localAuth = LocalAuthentication();
  String _enteredPin = '';
  String _errorMessage = '';
  bool _useBiometric = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool(AppConstants.prefBiometricEnabled) ?? false;

    if (biometricEnabled) {
      final canCheck = await _localAuth.canCheckBiometrics;
      final hasBiometrics = await _localAuth.isDeviceSupported();
      if (canCheck && hasBiometrics) {
        setState(() => _useBiometric = true);
        _authenticateWithBiometric();
      }
    }
  }

  Future<void> _authenticateWithBiometric() async {
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Unlock Daily Tracker',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (didAuthenticate && mounted) {
        widget.onUnlock();
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: $e');
      setState(() => _useBiometric = false);
    }
  }

  Future<void> _checkPin(String pinToCheck) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(AppConstants.prefAppLockPin);

    if (savedPin == null) {
      // No PIN set, just unlock
      widget.onUnlock();
      return;
    }

    if (CryptoUtils.verifyPin(pinToCheck, savedPin)) {
      widget.onUnlock();
    } else if (pinToCheck == savedPin) {
      // Backward compatibility: migrate plaintext PIN to hashed
      final hashedPin = CryptoUtils.hashPin(pinToCheck);
      await prefs.setString(AppConstants.prefAppLockPin, hashedPin);
      widget.onUnlock();
    } else {
      setState(() {
        _errorMessage = 'Incorrect PIN';
        _enteredPin = '';
      });
      HapticFeedback.mediumImpact();
    }
  }

  void _onDigitPressed(String digit) {
    if (_enteredPin.length >= 4) return;
    final newPin = _enteredPin + digit;
    setState(() {
      _enteredPin = newPin;
      _errorMessage = '';
    });
    if (newPin.length == 4) {
      _checkPin(newPin);
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(
                Icons.lock_outline,
                size: 64,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'App Locked',
                style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your PIN to continue',
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              PinDots(
                pinLength: _enteredPin.length,
                dotSize: 20,
                spacing: 12,
              ),
              const SizedBox(height: 16),
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              const Spacer(),
              NumpadGrid(
                onDigitPressed: _onDigitPressed,
                onBackspace: _onBackspace,
              ),
              const SizedBox(height: 16),
              if (_useBiometric)
                IconButton(
                  onPressed: _authenticateWithBiometric,
                  icon: const Icon(Icons.fingerprint, size: 40),
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

}
