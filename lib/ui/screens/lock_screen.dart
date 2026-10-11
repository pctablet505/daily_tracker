import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/lock_controller.dart';
import '../../state/providers.dart';
import '../theme/tokens.dart';

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
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            for (final k in const [
              '1',
              '2',
              '3',
              '4',
              '5',
              '6',
              '7',
              '8',
              '9',
              'back',
              '0',
              'ok',
            ])
              if (k == 'ok')
                Semantics(
                  button: true,
                  enabled: canSubmit,
                  label: widget.submitLabel,
                  excludeSemantics: true,
                  child: Material(
                    color: canSubmit ? c.accent : c.sunken,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: canSubmit
                          ? () {
                              final d = _digits;
                              setState(() => _digits = '');
                              widget.onSubmit(d);
                            }
                          : null,
                      child: Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: canSubmit ? c.onAccent : c.faint,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Semantics(
                  button: true,
                  label: k == 'back' ? 'Delete last digit' : 'Digit $k',
                  excludeSemantics: true,
                  child: Material(
                    color: c.sunken,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.enabled ? () => _key(k) : null,
                      child: Center(
                        child: k == 'back'
                            ? Icon(Icons.backspace_outlined, color: c.ink)
                            : Text(k, style: appText(24, 700, color: c.ink)),
                      ),
                    ),
                  ),
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

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pad = GlobalKey<PinPadState>();
  String? _error;
  Timer? _tick;
  Duration _wait = Duration.zero;
  bool _bio = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final lock = ref.read(lockServiceProvider);
    final available = await lock.biometricsAvailable;
    if (!mounted) return;
    setState(
      () => _bio = available && ref.read(settingsProvider).lockBiometric,
    );
    if (_bio) unawaited(_biometric());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _biometric() async {
    await ref.read(lockedProvider.notifier).unlockWithBiometrics();
  }

  void _countdown(Duration wait) {
    _tick?.cancel();
    setState(() => _wait = wait);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = _wait - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        t.cancel();
        if (mounted) {
          setState(() {
            _wait = Duration.zero;
            _error = null;
          });
        }
      } else if (mounted) {
        setState(() {
          _wait = left;
          _error = 'Too many tries. Wait ${_format(left)}.';
        });
      }
    });
  }

  String _format(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes} min ${d.inSeconds % 60} s';
    return '${d.inSeconds} s';
  }

  Future<void> _submit(String pin) async {
    final r = await ref.read(lockedProvider.notifier).unlockWithPin(pin);
    if (r.ok || !mounted) return;
    if (r.waitFor > Duration.zero) {
      setState(() => _error = 'Too many tries. Wait ${_format(r.waitFor)}.');
      _countdown(r.waitFor);
    } else {
      setState(() => _error = 'That PIN is not right.');
    }
    unawaited(HapticFeedback.heavyImpact());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
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
                      enabled: _wait == Duration.zero,
                      errorText: _error,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        if (_bio)
                          TextButton.icon(
                            onPressed: _biometric,
                            icon: const Icon(Icons.fingerprint_rounded),
                            label: const Text('Use fingerprint'),
                          ),
                        TextButton(
                          onPressed: () => unawaited(
                            ref
                                .read(lockedProvider.notifier)
                                .unlockWithDeviceCredential(),
                          ),
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
      ),
    );
  }
}
