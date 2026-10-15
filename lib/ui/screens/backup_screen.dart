import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backup_service.dart';
import '../../services/cloud_backup.dart';
import '../../services/drive_backup.dart';
import '../../services/files.dart';
import '../../state/lock_controller.dart';
import '../../state/providers.dart';
import '../../state/services.dart';
import '../format.dart';
import '../../core/day_key.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _status;
  bool _canUndo = false;
  DriveFileInfo? _otherOnDrive;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshUndo());
    unawaited(_lookForOtherBackup());
  }

  /// Notes a backup on Drive that this phone did not make, which automatic
  /// backup leaves alone. Offline or signed out, there is nothing to say.
  Future<void> _lookForOtherBackup() async {
    DriveFileInfo? other;
    try {
      if (_cloud.configured && _cloud.email != null) {
        other = await _cloud.otherBackupOnDrive();
      }
    } catch (e) {
      debugPrint('Could not look for a backup on Drive: $e');
    }
    if (mounted) setState(() => _otherOnDrive = other);
  }

  Future<void> _refreshUndo() async {
    var has = false;
    try {
      has = await ref.read(backupServiceProvider).hasSafetyCopy();
    } catch (e) {
      debugPrint('Could not look for a safety copy: $e');
    }
    if (mounted) setState(() => _canUndo = has);
  }

  CloudBackup get _cloud => ref.read(cloudBackupProvider);

  void _say(String m) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await job();
    } on FormatException catch (e) {
      _say(e.message);
    } on DriveException catch (e) {
      _say(e.message);
    } catch (e) {
      debugPrint('Backup screen action failed: $e');
      _say('That did not work. Nothing was changed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// When [p] was made, for a dialog.
  String _madeAt(BackupPreview p) {
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    final at = p.exportedAt.toLocal();
    return p.exportedAt.millisecondsSinceEpoch == 0
        ? 'an unknown date'
        : '${shortDate(DayKey.fromDate(at))}, ${formatMinutes(at.hour * 60 + at.minute, use24h: use24h)}';
  }

  Future<bool> _confirmReplace(BackupPreview p, String source) async {
    final when = _madeAt(p);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace everything on this phone?'),
        content: Text(
          'This backup from $source was made $when. It has ${plural(p.habits, 'habit')} and ${plural(p.entries, 'entry', 'entries')}.\n\n'
          'Your current habits and history, and your reminder, streak and theme settings, are replaced. A safety copy of them is kept on this phone, and "Undo the last restore" puts it back. Photos are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.danger),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _saveFile() => _run(() async {
    final f = await ref.read(backupServiceProvider).export();
    if (!mounted) return;
    await ref
        .read(lockedProvider.notifier)
        .runExternal(
          () => ref
              .read(fileServiceProvider)
              .shareText(f.fileName, f.text, subject: 'Daily Tracker backup'),
        );
  });

  Future<void> _restoreFile() => _run(() async {
    final text = await ref
        .read(lockedProvider.notifier)
        .runExternal(() => ref.read(fileServiceProvider).pickAndReadText());
    if (text == null || !mounted) return;
    final service = ref.read(backupServiceProvider);
    final preview = service.preview(text);
    if (!mounted || !await _confirmReplace(preview, 'the file')) return;
    await service.restore(text);
    _say('Restored ${plural(preview.habits, 'habit')}.');
    await _refreshUndo();
  });

  Future<void> _undoRestore() => _run(() async {
    final service = ref.read(backupServiceProvider);
    final p = await service.lastRestorePreview();
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo the last restore?'),
        content: Text(
          'The copy from before the last restore was made ${_madeAt(p)}. It has ${plural(p.habits, 'habit')} and ${plural(p.entries, 'entry', 'entries')}.\n\n'
          'Those habits and history, and your reminder, streak and theme settings, are put back. What is here now is replaced, and kept as a copy you can undo again. Photos are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Undo the restore'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await service.undoLastRestore();
    _say('Put back what was here before the last restore.');
    await _refreshUndo();
  });

  Future<void> _signIn() => _run(() async {
    final email = await ref
        .read(lockedProvider.notifier)
        .runExternal(_cloud.signIn);
    _say('Signed in as $email.');
    await _lookForOtherBackup();
  });

  Future<void> _signOut() => _run(() async {
    await _cloud.signOut();
  });

  /// Asks whether to [action] over mobile data although backups wait for Wi-Fi.
  Future<bool> _useMobileData(String action) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not on Wi-Fi'),
        content: Text(
          'Your backup is set to wait for Wi-Fi. $action over mobile data instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Wait for Wi-Fi'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use mobile data'),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _backupNow({bool overrideWifi = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Backing up...';
    });
    try {
      final r = await _cloud.backupNow(overrideWifiOnly: overrideWifi);
      if (!mounted) return;
      switch (r.status) {
        case BackupStatus.done:
          setState(() => _otherOnDrive = null);
          _say('Backed up to Google Drive.');
        case BackupStatus.waitingForWifi:
          final go = await _useMobileData('Back up now');
          if (go && mounted) {
            setState(() => _busy = false);
            return await _backupNow(overrideWifi: true);
          }
        case BackupStatus.offline:
          _say('You are offline. Try again when you are connected.');
        case BackupStatus.signInNeeded:
          _say(r.message.isEmpty ? 'Sign in to Google again.' : r.message);
        case BackupStatus.failed:
          _say(r.message.isEmpty ? 'The backup failed.' : r.message);
      }
    } catch (e) {
      debugPrint('Backup failed: $e');
      _say('The backup failed.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _restoreDrive() => _run(() async {
    CloudRestore? fetched;
    try {
      fetched = await _cloud.fetchForRestore();
    } on DriveException catch (e) {
      if (!e.needsWifi) rethrow;
      if (!mounted || !await _useMobileData('Restore now')) return;
      fetched = await _cloud.fetchForRestore(overrideWifiOnly: true);
    }
    if (fetched == null) {
      _say('There is no backup on Google Drive yet.');
      return;
    }
    if (!mounted || !await _confirmReplace(fetched.preview, 'Google Drive'))
      return;
    await _cloud.restore(fetched.text);
    await _cloud.restoredFrom(fetched.file);
    if (mounted) setState(() => _otherOnDrive = null);
    _say(
      'Restored ${plural(fetched.preview.habits, 'habit')} from Google Drive.',
    );
    await _refreshUndo();
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cloud = ref.watch(cloudBackupProvider);
    ref.watch(settingsProvider);
    final s = ref.read(settingsProvider);
    final last = cloud.lastBackupAt;
    final autoFailure = cloud.lastAutoBackupFailure;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.photo_camera_back_outlined, color: c.accentInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Photos stay on this phone. Backups hold your habits, entries and settings, not the pictures.',
                    style: AppType.small.copyWith(
                      color: c.accentInk,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(
            'A file on this phone',
            padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
          ),
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Save a copy anywhere you like: Drive, email, a USB drive. It is plain, readable JSON.',
                  style: AppType.small.copyWith(color: c.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _saveFile,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Save a backup file'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restoreFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Restore from a file'),
                ),
                if (_canUndo) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : _undoRestore,
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Undo the last restore'),
                  ),
                ],
              ],
            ),
          ),
          const SectionHeader(
            'Google Drive',
            padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
          ),
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!cloud.configured)
                  Text(
                    'Google Drive backup is not set up in this build of the app. The backup file above works without it. The README explains how to turn it on.',
                    style: AppType.small.copyWith(color: c.muted, height: 1.4),
                  )
                else if (cloud.email == null) ...[
                  Text(
                    'Keep an automatic copy in a private folder of your own Google Drive. Only this app can see it.',
                    style: AppType.small.copyWith(color: c.muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Sign in with Google'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Icon(Icons.account_circle_outlined, color: c.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cloud.email!,
                          style: AppType.body,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _signOut,
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                  if (_otherOnDrive case final other?)
                    Text(
                      'A backup from ${shortDate(DayKey.fromDate(other.modified.toLocal()))} is on Drive. Automatic backup leaves it alone; Back up now replaces it.',
                      style: AppType.small.copyWith(color: c.muted),
                    ),
                  if (last != null || _otherOnDrive == null)
                    Text(
                      last == null
                          ? 'Not backed up yet.'
                          : 'Last backup: ${shortDate(DayKey.fromDate(last.toLocal()))}',
                      style: AppType.small.copyWith(color: c.muted),
                    ),
                  if (autoFailure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'The last automatic backup did not work: $autoFailure',
                        style: AppType.small.copyWith(color: c.danger),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Signing in again, not out and in, keeps automatic backup on.
                  if (cloud.sessionLost) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : _signIn,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Sign in again'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _busy ? null : _backupNow,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(_status ?? 'Back up now'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreDrive,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Restore from Google Drive'),
                  ),
                  const SizedBox(height: 4),
                  // The card's colour would hide the switches' ink.
                  Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Back up automatically',
                            style: AppType.body,
                          ),
                          subtitle: Text(
                            'About once a day, when you open the app.',
                            style: AppType.small.copyWith(color: c.muted),
                          ),
                          value: cloud.autoBackup,
                          onChanged: (v) async {
                            await cloud.setAutoBackup(v);
                            if (mounted) setState(() {});
                          },
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Only on Wi-Fi', style: AppType.body),
                          value: s.wifiOnlyBackup,
                          onChanged: (v) => ref
                              .read(settingsProvider.notifier)
                              .update((x) => x.copyWith(wifiOnlyBackup: v)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
