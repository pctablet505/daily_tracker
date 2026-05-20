import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/dependency_injection.dart';
import '../../../core/services/export_service.dart';
import '../../../data/local/database_helper.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildSectionHeader(context, 'Appearance'),
          _ThemeSelector(
            themeMode: themeState.themeMode,
            onThemeChanged: themeNotifier.setThemeMode,
          ),
          const Divider(),
          _buildSectionHeader(context, 'Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Enable Notifications'),
            subtitle: const Text('Get reminded about your tasks'),
            value: settings.notificationsEnabled,
            onChanged: settingsNotifier.setNotificationsEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.do_not_disturb_on_outlined),
            title: const Text('Quiet Hours'),
            subtitle: Text(
              settings.quietHoursStart != null && settings.quietHoursEnd != null
                  ? '${_formatTime(settings.quietHoursStart!)} - ${_formatTime(settings.quietHoursEnd!)}'
                  : 'Not set',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showQuietHoursPicker(context, ref, settings, settingsNotifier),
          ),
          const Divider(),
          _buildSectionHeader(context, 'Security'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App Lock'),
            subtitle: const Text('Require PIN to open app'),
            value: settings.appLockEnabled,
            onChanged: settingsNotifier.setAppLockEnabled,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric Unlock'),
            subtitle: const Text('Use fingerprint or face recognition'),
            value: settings.biometricEnabled,
            onChanged: settings.biometricEnabled
                ? settingsNotifier.setBiometricEnabled
                : null,
          ),
          const Divider(),
          _buildSectionHeader(context, 'Data & Sync'),
          SwitchListTile(
            secondary: const Icon(Icons.sync_outlined),
            title: const Text('Auto Sync'),
            subtitle: const Text('Automatically sync with Google Drive'),
            value: settings.autoSync,
            onChanged: settingsNotifier.setAutoSync,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Wi-Fi Only Sync'),
            subtitle: const Text('Only sync when connected to Wi-Fi'),
            value: settings.wifiOnlySync,
            onChanged: settingsNotifier.setWifiOnlySync,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Manual Sync'),
            subtitle: const Text('Sync now with Google Drive'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sync requires Google Sign-In')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export Data'),
            subtitle: const Text('Export as JSON or CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showExportDialog(context),
          ),
          const Divider(),
          _buildSectionHeader(context, 'Updates'),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_tethering),
            title: const Text('Wi-Fi Only Updates'),
            subtitle: const Text('Only download updates on Wi-Fi'),
            value: settings.wifiOnlyUpdates,
            onChanged: settingsNotifier.setWifiOnlyUpdates,
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Check for Updates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Update check will be available in the next phase')),
              );
            },
          ),
          const Divider(),
          _buildSectionHeader(context, 'About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            trailing: Text('1.0.0'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _showQuietHoursPicker(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
    SettingsNotifier notifier,
  ) async {
    TimeOfDay? start = settings.quietHoursStart != null
        ? TimeOfDay.fromDateTime(settings.quietHoursStart!)
        : const TimeOfDay(hour: 22, minute: 0);
    TimeOfDay? end = settings.quietHoursEnd != null
        ? TimeOfDay.fromDateTime(settings.quietHoursEnd!)
        : const TimeOfDay(hour: 7, minute: 0);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quiet Hours'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Start Time'),
              trailing: Text(start?.format(context) ?? '22:00'),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: start ?? const TimeOfDay(hour: 22, minute: 0),
                );
                if (picked != null) start = picked;
              },
            ),
            ListTile(
              title: const Text('End Time'),
              trailing: Text(end?.format(context) ?? '07:00'),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: end ?? const TimeOfDay(hour: 7, minute: 0),
                );
                if (picked != null) end = picked;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final now = DateTime.now();
              notifier.setQuietHours(
                DateTime(now.year, now.month, now.day, start!.hour, start!.minute),
                DateTime(now.year, now.month, now.day, end!.hour, end!.minute),
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Export as JSON'),
              subtitle: const Text('Full backup including tasks and history'),
              onTap: () async {
                Navigator.pop(context);
                final exportService = ExportService(getIt<DatabaseHelper>());
                await exportService.shareJsonExport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Export as CSV'),
              subtitle: const Text('Analytics data only'),
              onTap: () async {
                Navigator.pop(context);
                final exportService = ExportService(getIt<DatabaseHelper>());
                await exportService.shareCsvExport();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const _ThemeSelector({
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            label: Text('Light'),
            icon: Icon(Icons.light_mode),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            label: Text('Auto'),
            icon: Icon(Icons.brightness_auto),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text('Dark'),
            icon: Icon(Icons.dark_mode),
          ),
        ],
        selected: {themeMode},
        onSelectionChanged: (newSelection) {
          onThemeChanged(newSelection.first);
        },
        multiSelectionEnabled: false,
      ),
    );
  }
}
