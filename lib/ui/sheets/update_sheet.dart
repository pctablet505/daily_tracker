import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/updater.dart';
import '../../state/lock_controller.dart';
import '../../state/providers.dart';
import '../../state/services.dart';
import '../theme/tokens.dart';

/// Shows a new release and lets the user download and install it. Not blocking: it can always be closed.
Future<void> showUpdateSheet(
  BuildContext context,
  ReleaseInfo release, {
  Future<void> Function()? onSkip,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    builder: (_) => _UpdateSheet(release: release, onSkip: onSkip),
  );
}

enum _Phase { idle, downloading, ready, error }

class _UpdateSheet extends ConsumerStatefulWidget {
  const _UpdateSheet({required this.release, this.onSkip});
  final ReleaseInfo release;
  final Future<void> Function()? onSkip;

  @override
  ConsumerState<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<_UpdateSheet> {
  _Phase _phase = _Phase.idle;
  double? _progress;
  String? _error;
  File? _file;
  CancelToken? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    final wifiOnly = ref.read(settingsProvider).wifiOnlyUpdate;
    if (wifiOnly && !await ref.read(networkProvider).isOnWifi()) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error =
            'Connect to Wi-Fi to download, or turn off "Update over Wi-Fi only" in Settings.';
      });
      return;
    }
    if (!mounted) return;
    final token = _cancel = CancelToken();
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
      _error = null;
    });
    try {
      final f = await ref
          .read(updateServiceProvider)
          .download(
            widget.release,
            cancel: token,
            onProgress: (got, total) {
              if (mounted && total > 0) {
                setState(() => _progress = (got / total).clamp(0.0, 1.0));
              }
            },
          );
      if (!mounted) return;
      setState(() {
        _file = f;
        _phase = _Phase.ready;
      });
      await _install();
    } on UpdateCancelled {
      if (mounted) setState(() => _phase = _Phase.idle);
    } on UpdateException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e.message;
        });
      }
    } catch (e) {
      debugPrint('Update download failed: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = 'The download failed.';
        });
      }
    }
  }

  Future<void> _install() async {
    final f = _file;
    if (f == null) return;
    final problem = await ref
        .read(lockedProvider.notifier)
        .runExternal(
          () => ref.read(updateServiceProvider).install(f),
          opensActivity: true,
        );
    if (problem != null && mounted) {
      setState(() {
        _phase = _Phase.error;
        _error = problem;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.release;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_rounded, color: c.accentInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Version ${r.version} is available',
                    style: AppType.title,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'What is new',
              style: AppType.overline.copyWith(color: c.muted),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  r.notes,
                  style: AppType.bodyLight.copyWith(height: 1.4),
                ),
              ),
            ),
            if (r.apkSize != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${(r.apkSize! / (1024 * 1024)).toStringAsFixed(1)} MB',
                  style: AppType.small.copyWith(color: c.faint),
                ),
              ),
            const SizedBox(height: 16),
            if (_phase == _Phase.downloading) ...[
              LinearProgressIndicator(
                value: _progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? 'Starting the download...'
                    : 'Downloading ${(_progress! * 100).round()}%',
                style: AppType.small.copyWith(color: c.muted),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _cancel?.cancel(),
                child: const Text('Cancel'),
              ),
            ] else ...[
              if (_phase == _Phase.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: c.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error ?? 'Something went wrong.',
                          style: AppType.small.copyWith(color: c.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              FilledButton(
                onPressed:
                    _phase == _Phase.ready ||
                        (_phase == _Phase.error && _file != null)
                    ? _install
                    : _download,
                child: Text(switch (_phase) {
                  _Phase.ready => 'Install',
                  _Phase.error =>
                    _file != null ? 'Try installing again' : 'Try again',
                  _ => 'Download and install',
                }),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_phase == _Phase.idle ? 'Not now' : 'Close'),
              ),
              if ((_phase == _Phase.idle || _phase == _Phase.error) &&
                  widget.onSkip != null)
                TextButton(
                  onPressed: () async {
                    await widget.onSkip!();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Skip this version'),
                ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Your habits stay on this phone. Android asks you to confirm the install.',
                style: AppType.caption.copyWith(color: c.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
