import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/lock_controller.dart';
import '../../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/keypad.dart';

/// Dots and a keypad for entering a 4 to 6 digit PIN. Calls [onSubmit] with the digits when the user presses OK.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmit,
    this.enabled = true,
    this.errorText,
    this.submitLabel = 'OK',
  });
  final ValueChanged<String> onSubmit;
  final bool enabled;
  final String? errorText;
  final String submitLabel;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _digits = '';

  void clear() => setState(() => _digits = '');

  void _key(String k) {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (k == 'back') {
        if (_digits.isNotEmpty)
          _digits = _digits.substring(0, _digits.length - 1);
      } else if (_digits.length < 6) {
        _digits += k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canSubmit = widget.enabled && _digits.length >= 4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: _digits.isEmpty
              ? 'No digits entered'
              : '${_digits.length} digits entered',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 6; i++)
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _digits.length
                            ? c.accent
                            : Colors.transparent,
                        border: Border.all(
                          color: i < _digits.length ? c.accent : c.border2,
                          width: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: widget.errorText == null
              ? null
              : Center(
                  child: Text(
                    widget.errorText!,
                    textAlign: TextAlign.center,
                    style: AppType.small.copyWith(color: c.danger),
                  ),
                ),
        ),
        Keypad(
          aspectRatio: 1.7,
          keys: [
            for (final d in const ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
              PadKey.digit(d, widget.enabled ? () => _key(d) : null),
            PadKey.backspace(widget.enabled ? () => _key('back') : null),
            PadKey.digit('0', widget.enabled ? () => _key('0') : null),
            PadKey(
              widget.submitLabel,
              canSubmit
                  ? () {
                      final d = _digits;
                      setState(() => _digits = '');
                      widget.onSubmit(d);
                    }
                  : null,
              icon: Icons.check_rounded,
              primary: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// Covers the app while it is locked.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with WidgetsBindingObserver {
  final _pad = GlobalKey<PinPadState>();
  String? _error;
  Timer? _tick;
  Duration _wait = Duration.zero;
  bool _bioAvailable = false;

  /// A fingerprint or phone lock prompt is up; a second one would fail as busy.
  bool _checking = false;

  /// A PIN is being checked; guesses wait for its answer and the wait it may start.
  bool _checkingPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  Future<void> _init() async {
    final lock = ref.read(lockServiceProvider);
    await _showWait();
    final available = await lock.biometricsAvailable;
    if (!mounted) return;
    setState(() => _bioAvailable = available);
    if (available && ref.read(settingsProvider).lockBiometric) {
      unawaited(_biometric());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) unawaited(_showWait());
  }

  Future<void> _biometric() async {
    if (_checking) return;
    _checking = true;
    try {
      await ref.read(lockedProvider.notifier).unlockWithBiometrics();
    } finally {
      _checking = false;
    }
  }

  /// Shows the wrong-PIN wait as the lock service has it now (the screen may
  /// have been off meanwhile) and keeps it ticking until it is over.
  Future<void> _showWait() async {
    final wait = await ref.read(lockServiceProvider).waitLeft();
    if (!mounted) return;
    if (wait > Duration.zero) {
      setState(() {
        _wait = wait;
        _error = 'Too many tries. Wait ${_format(wait)}.';
      });
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_showWait()),
      );
    } else {
      _tick?.cancel();
      _tick = null;
      if (_wait > Duration.zero) {
        setState(() {
          _wait = Duration.zero;
          _error = null;
        });
      }
    }
  }

  String _format(Duration d) {
    final totalSeconds = (d.inMilliseconds / 1000).ceil().clamp(1, 360000);
    if (totalSeconds >= 60) {
      return '${totalSeconds ~/ 60} min ${totalSeconds % 60} s';
    }
    return '$totalSeconds s';
  }

  Future<void> _submit(String pin) async {
    if (_checkingPin) return;
    setState(() => _checkingPin = true);
    try {
      final r = await ref.read(lockedProvider.notifier).unlockWithPin(pin);
      if (r.ok || !mounted) return;
      if (r.waitFor > Duration.zero) {
        await _showWait();
      } else {
        setState(() => _error = 'That PIN is not right.');
      }
      unawaited(HapticFeedback.heavyImpact());
    } finally {
      if (mounted) setState(() => _checkingPin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fingerprintOn = ref.watch(
      settingsProvider.select((s) => s.lockBiometric),
    );
    final showBio = _bioAvailable && fingerprintOn;
    final showPhoneLock = ref.watch(phoneLockAllowedProvider).value ?? false;
    // Not a Scaffold: the app's ScaffoldMessenger would show its snackbars
    // (habit names, an Undo) on this one too.
    return Material(
      color: c.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: c.accentInk,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      'Daily Tracker is locked',
                      style: AppType.title,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your PIN',
                    style: AppType.bodyLight.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: 16),
                  PinPad(
                    key: _pad,
                    onSubmit: _submit,
                    enabled: _wait == Duration.zero && !_checkingPin,
                    errorText: _error,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      if (showBio)
                        TextButton.icon(
                          onPressed: _biometric,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Use fingerprint'),
                        ),
                      if (showPhoneLock)
                        TextButton(
                          onPressed: () => unawaited(_deviceCredential()),
                          child: const Text('Forgot PIN? Use phone lock'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deviceCredential() async {
    if (_checking) return;
    _checking = true;
    try {
      final ok = await ref
          .read(lockedProvider.notifier)
          .unlockWithDeviceCredential();
      if (!ok && mounted) {
        setState(() => _error = 'Could not unlock with your phone lock.');
      }
    } finally {
      _checking = false;
    }
  }
}
