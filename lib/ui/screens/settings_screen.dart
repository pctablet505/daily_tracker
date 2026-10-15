import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/files.dart';
import '../../services/reminder_sync.dart';
import '../../services/updater.dart';
import '../../state/lock_controller.dart';
import '../../state/providers.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../format.dart';
import '../sheets/update_sheet.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'lock_screen.dart';

/// Whether notifications are allowed right now. Re-read after the app returns from system settings.
final notificationsAllowedProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(reminderSchedulerProvider).hasPermission(),
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _checkingUpdate = false;

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
    if (state == AppLifecycleState.resumed)
      ref.invalidate(notificationsAllowedProvider);
  }

  Future<void> _set(Settings Function(Settings) change) =>
      ref.read(settingsProvider.notifier).update(change);

  Future<void> _pickTime(int current, ValueChanged<int> onPicked) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t != null && mounted) onPicked(t.hour * 60 + t.minute);
  }

  Future<void> _allowNotifications() async {
    final ok = await ref
        .read(lockedProvider.notifier)
        .runExternal(
          () => ref.read(reminderSchedulerProvider).requestPermission(),
        );
    if (!mounted) return;
    ref.invalidate(notificationsAllowedProvider);
    if (!ok) {
      await ref
          .read(lockedProvider.notifier)
          .runExternal(openAppSettings, opensActivity: true);
      if (!mounted) return;
      ref.invalidate(notificationsAllowedProvider);
    }
    unawaited(ref.read(reminderSyncProvider).resync());
  }

  Future<void> _toggleLock(bool on) async {
    final lock = ref.read(lockServiceProvider);
    if (on) {
      final pin = await showPinSetup(context);
      if (pin == null || !mounted) return;
      await lock.setPin(pin);
      if (!mounted) return;
      await _set((s) => s.copyWith(lockOn: true));
    } else {
      final ok = await _confirmPin();
      if (!ok || !mounted) return;
      await _set((s) => s.copyWith(lockOn: false));
      await lock.clearPin();
    }
  }

  Future<bool> _confirmPin({
    String title = 'Enter your PIN to turn the lock off',
  }) async {
    final pin = await showPinEntry(context, title: title);
    if (pin == null || !mounted) return false;
    if (pin == _phoneLockToken) {
      final ok = await ref
          .read(lockedProvider.notifier)
          .unlockWithDeviceCredential();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not unlock with your phone lock.'),
          ),
        );
      }
      return ok;
    }
    final r = await ref.read(lockServiceProvider).checkPin(pin);
    if (!r.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.waitFor > Duration.zero
                ? 'Too many tries. Wait a little.'
                : 'That PIN is not right.',
          ),
        ),
      );
    }
    return r.ok;
  }

  Future<void> _changePin() async {
    if (!await _confirmPin(title: 'Enter your current PIN')) return;
    if (!mounted) return;
    final pin = await showPinSetup(context);
    if (pin != null && mounted) {
      await ref.read(lockServiceProvider).setPin(pin);
    }
  }

  Future<void> _exportCsv() async {
    try {
      final f = await ref.read(backupServiceProvider).exportCsv();
      if (!mounted) return;
      await ref
          .read(lockedProvider.notifier)
          .runExternal(
            () => ref
                .read(fileServiceProvider)
                .shareText(
                  f.fileName,
                  f.text,
                  subject: 'Daily Tracker entries',
                  mimeType: 'text/csv',
                ),
          );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the file.')),
        );
    }
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final r = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    switch (r) {
      case UpdateAvailable(:final release):
        await showUpdateSheet(context, release);
      case UpToDate():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have the latest version.')),
        );
      case UpdateCheckFailed(:final message):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    final allowed = ref.watch(notificationsAllowedProvider).value ?? true;
    final version = ref.watch(appVersionProvider).value;
    String t(int m) => formatMinutes(m, use24h: use24h);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Group('Look'),
          _Card([
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<ThemeChoice>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeChoice.light, label: Text('Light')),
                  ButtonSegment(
                    value: ThemeChoice.system,
                    label: Text('System'),
                  ),
                  ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
                ],
                selected: {s.theme},
                onSelectionChanged: (v) =>
                    _set((x) => x.copyWith(theme: v.first)),
              ),
            ),
          ]),
          const _Group('Streaks'),
          _Card([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A day keeps your streak at ${s.streakThreshold}%',
                    style: AppType.body,
                  ),
                  Text(
                    'of your planned habits done. Days with nothing planned are skipped.',
                    style: AppType.small.copyWith(color: c.muted),
                  ),
                  Semantics(
                    label: 'Share of habits that keeps a streak',
                    value: '${s.streakThreshold} percent',
                    child: Slider(
                      value: s.streakThreshold.toDouble().clamp(10, 100),
                      min: 10,
                      max: 100,
                      divisions: 9,
                      label: '${s.streakThreshold}%',
                      onChanged: (v) =>
                          _set((x) => x.copyWith(streakThreshold: v.round())),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const _Group('Reminders'),
          _Card([
            if (!allowed)
              _Row(
                icon: Icons.notifications_off_outlined,
                title: 'Notifications are off',
                subtitle: 'Turn them on or no reminder can show.',
                trailing: FilledButton.tonal(
                  onPressed: _allowNotifications,
                  child: const Text('Turn on'),
                ),
              ),
            _SwitchRow(
              icon: Icons.notifications_outlined,
              title: 'Reminders',
              subtitle: 'Set a time on a habit to be reminded.',
              value: s.remindersOn,
              onChanged: (v) => _set((x) => x.copyWith(remindersOn: v)),
            ),
            _SwitchRow(
              icon: Icons.bedtime_outlined,
              title: 'Quiet hours',
              subtitle: s.quietHoursOn
                  ? 'No reminders from ${t(s.quietStartMinutes)} to ${t(s.quietEndMinutes)}'
                  : 'Hold reminders back at night.',
              value: s.quietHoursOn,
              onChanged: (v) => _set((x) => x.copyWith(quietHoursOn: v)),
            ),
            if (s.quietHoursOn) ...[
              _Row(
                title: 'From',
                subtitle: t(s.quietStartMinutes),
                onTap: () => _pickTime(
                  s.quietStartMinutes,
                  (m) => _set((x) => x.copyWith(quietStartMinutes: m)),
                ),
              ),
              _Row(
                title: 'Until',
                subtitle: t(s.quietEndMinutes),
                onTap: () => _pickTime(
                  s.quietEndMinutes,
                  (m) => _set((x) => x.copyWith(quietEndMinutes: m)),
                ),
              ),
            ],
            _SwitchRow(
              icon: Icons.nights_stay_outlined,
              title: 'Evening check-in',
              subtitle: s.eveningCheckInOn
                  ? 'Asks at ${t(s.eveningCheckInMinutes)} how the day went, if you stay clear of anything.'
                  : 'Off',
              value: s.eveningCheckInOn,
              onChanged: (v) => _set((x) => x.copyWith(eveningCheckInOn: v)),
            ),
            if (s.eveningCheckInOn)
              _Row(
                title: 'Check-in time',
                subtitle: t(s.eveningCheckInMinutes),
                onTap: () => _pickTime(
                  s.eveningCheckInMinutes,
                  (m) => _set((x) => x.copyWith(eveningCheckInMinutes: m)),
                ),
              ),
          ]),
          const _Group('Lock'),
          _Card([
            _SwitchRow(
              icon: Icons.lock_outline_rounded,
              title: 'App lock',
              subtitle: 'Ask for a PIN when the app opens.',
              value: s.lockOn,
              onChanged: _toggleLock,
            ),
            if (s.lockOn) ...[
              _SwitchRow(
                icon: Icons.fingerprint_rounded,
                title: 'Use fingerprint',
                subtitle: 'If your phone has one set up.',
                value: s.lockBiometric,
                onChanged: (v) => _set((x) => x.copyWith(lockBiometric: v)),
              ),
              _Row(
                title: 'Lock after',
                subtitle: _lockAfterLabel(s.lockAfterSeconds),
                onTap: () async {
                  final v = await showDialog<int>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Lock after leaving the app for'),
                      children: [
                        for (final e in const {
                          0: 'Right away',
                          60: '1 minute',
                          300: '5 minutes',
                          900: '15 minutes',
                        }.entries)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, e.key),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(e.value, style: AppType.body),
                                ),
                                if (e.key == s.lockAfterSeconds)
                                  Icon(
                                    Icons.check_rounded,
                                    color: ctx.colors.accent,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                  if (v != null && mounted)
                    await _set((x) => x.copyWith(lockAfterSeconds: v));
                },
              ),
              _Row(title: 'Change PIN', onTap: _changePin),
            ],
          ]),
          const _Group('Your data'),
          _Card([
            _Row(
              icon: Icons.cloud_upload_outlined,
              title: 'Backup and restore',
              subtitle: 'A file on this phone, or Google Drive.',
              onTap: () => context.push('/settings/backup'),
            ),
            _Row(
              icon: Icons.table_chart_outlined,
              title: 'Export entries as a spreadsheet',
              subtitle: 'A CSV file of every entry.',
              onTap: _exportCsv,
            ),
          ]),
          const _Group('App'),
          _Card([
            _Row(
              icon: Icons.system_update_outlined,
              title: 'Check for updates',
              subtitle: version == null ? null : 'Version $version',
              trailing: _checkingUpdate
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : null,
              onTap: _checkingUpdate ? null : _checkUpdate,
            ),
            _SwitchRow(
              icon: Icons.wifi_rounded,
              title: 'Update over Wi-Fi only',
              subtitle: 'Do not download updates on mobile data.',
              value: s.wifiOnlyUpdate,
              onChanged: (v) => _set((x) => x.copyWith(wifiOnlyUpdate: v)),
            ),
            _Row(
              icon: Icons.code_rounded,
              title: 'Source code',
              subtitle: sourceUrl,
              onTap: () => ref
                  .read(lockedProvider.notifier)
                  .runExternal(
                    () => launchUrl(
                      Uri.parse(sourceUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    opensActivity: true,
                  ),
            ),
            _Row(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy',
              subtitle: 'Your habits stay on this phone.',
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Privacy'),
                  content: const Text(
                    'Your habits, entries and photos are stored only on this phone. '
                    'The app has no account and sends nothing anywhere on its own.\n\n'
                    'If you choose Google Drive backup, a copy of your habits and entries (not your photos) goes to a private folder in your own Drive that only this app can read.\n\n'
                    'Android may also include your habits and entries (never your photos, settings or PIN) in your Google account\'s automatic phone backup. You can turn that off in your phone\'s system settings.\n\n'
                    'Checking for updates asks GitHub for the latest release.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
            _Row(
              icon: Icons.description_outlined,
              title: 'Open-source licences',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Daily Tracker',
                applicationVersion: version,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  String _lockAfterLabel(int s) => switch (s) {
    0 => 'Right away',
    60 => '1 minute',
    300 => '5 minutes',
    900 => '15 minutes',
    _ => '${s ~/ 60} minutes',
  };
}

class _Group extends StatelessWidget {
  const _Group(this.title);
  final String title;

  @override
  Widget build(BuildContext context) =>
      SectionHeader(title, padding: const EdgeInsets.fromLTRB(24, 20, 24, 8));
}

class _Card extends StatelessWidget {
  const _Card(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SurfaceCard(
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: c.muted),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.body),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppType.small.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: c.muted),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppType.body),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppType.small.copyWith(color: c.muted),
                        ),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a new PIN twice. Returns it, or null when cancelled.
Future<String?> showPinSetup(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const _PinSetup(),
  );
}

const _phoneLockToken = '__phone_lock__';

/// Asks for a PIN once. Returns it, or null when cancelled.
Future<String?> showPinEntry(BuildContext context, {required String title}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppType.title, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              PinPad(onSubmit: (p) => Navigator.pop(ctx, p)),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _phoneLockToken),
                child: const Text('Forgot PIN? Use phone lock'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PinSetup extends StatefulWidget {
  const _PinSetup();

  @override
  State<_PinSetup> createState() => _PinSetupState();
}

class _PinSetupState extends State<_PinSetup> {
  String? _first;
  String? _error;

  void _submit(String pin) {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
    } else if (_first == pin) {
      Navigator.pop(context, pin);
    } else {
      setState(() {
        _first = null;
        _error = 'The two PINs did not match. Start again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _first == null ? 'Choose a PIN' : 'Enter it again',
                style: AppType.title,
              ),
              const SizedBox(height: 4),
              Text(
                '4 to 6 digits. If you forget it, your phone lock can unlock the app.',
                textAlign: TextAlign.center,
                style: AppType.small.copyWith(color: c.muted),
              ),
              const SizedBox(height: 12),
              PinPad(
                key: ValueKey(_first == null),
                onSubmit: _submit,
                errorText: _error,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
