import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/dependency_injection.dart';
import '../../../core/services/export_service.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/sync/sync_service.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/theme_provider.dart';
import '../../../presentation/features/update/update_dialog.dart';
import '../../../presentation/features/lock/pin_setup_dialog.dart';

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
            onChanged: (value) async {
              if (value) {
                // Enabling — show PIN setup
                final success = await PinSetupDialog.show(context);
                if (success) {
                  settingsNotifier.setAppLockEnabled(true);
                }
              } else {
                // Disabling — clear PIN
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove(AppConstants.prefAppLockPin);
                await prefs.setBool(AppConstants.prefBiometricEnabled, false);
                settingsNotifier.setAppLockEnabled(false);
                settingsNotifier.setBiometricEnabled(false);
              }
            },
          ),
          FutureBuilder<bool>(
            future: _canUseBiometric(),
            builder: (context, snapshot) {
              final canUseBiometric = snapshot.data ?? false;
              return SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Biometric Unlock'),
                subtitle: Text(
                  canUseBiometric
                      ? 'Use fingerprint or face recognition'
                      : 'Not available on this device',
                ),
                value: settings.biometricEnabled,
                onChanged: settings.appLockEnabled && canUseBiometric
                    ? settingsNotifier.setBiometricEnabled
                    : null,
              );
            },
          ),
          const Divider(),
          _buildSectionHeader(context, 'Data & Sync'),
          _buildSyncStatusTile(context, ref),
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
            onTap: () => _showSyncDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export Data'),
            subtitle: const Text('Export as JSON or CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showExportDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Import Data'),
            subtitle: const Text('Restore from JSON backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _importData(context, ref),
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
            onTap: () => _checkForUpdates(context, ref),
          ),
          const Divider(),
          _buildSectionHeader(context, 'About'),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.hasData
                  ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                  : '1.0.0';
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                trailing: Text(version),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Source Code'),
            subtitle: const Text('View on GitHub'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final uri = Uri.parse(
                'https://github.com/${AppConstants.githubOwner}/${AppConstants.githubRepo}',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy'),
            subtitle: const Text('Data stays on your device and Google Drive'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<bool> _canUseBiometric() async {
    final localAuth = LocalAuthentication();
    final canCheck = await localAuth.canCheckBiometrics;
    final isSupported = await localAuth.isDeviceSupported();
    return canCheck && isSupported;
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
    final initialStart = settings.quietHoursStart != null
        ? TimeOfDay.fromDateTime(settings.quietHoursStart!)
        : const TimeOfDay(hour: 22, minute: 0);
    final initialEnd = settings.quietHoursEnd != null
        ? TimeOfDay.fromDateTime(settings.quietHoursEnd!)
        : const TimeOfDay(hour: 7, minute: 0);

    final result = await showDialog<_QuietHoursResult>(
      context: context,
      builder: (context) => _QuietHoursDialog(
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );

    if (result != null) {
      final now = DateTime.now();
      notifier.setQuietHours(
        DateTime(now.year, now.month, now.day, result.start.hour, result.start.minute),
        DateTime(now.year, now.month, now.day, result.end.hour, result.end.minute),
      );
    }
  }

  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Checking for updates...'), duration: Duration(seconds: 2)),
    );

    final service = UpdateService();
    final update = await service.checkForUpdate();

    if (!context.mounted) return;

    if (update != null) {
      await UpdateDialog.show(context, update);
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('You are on the latest version')),
      );
    }
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      if (!context.mounted) return;

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
          title: const Text('Overwrite Data?'),
          content: const Text(
            'Importing will replace all existing tasks, completion history, and logs. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Importing data...'),
              ],
            ),
          ),
        ),
      );

      final jsonString = await File(file.path!).readAsString();
      final exportService = ExportService(getIt<DatabaseHelper>());
      final success = await exportService.importFromJson(jsonString);

      if (!context.mounted) return;
      Navigator.pop(context); // dismiss loading dialog

      if (success) {
        // Refresh all providers
        ref.read(taskActionsProvider).refreshAllTaskProviders();
        ref.invalidate(allTaskLogsProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data imported successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed. Invalid backup file.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        // Dismiss loading dialog if still showing
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e')),
        );
      }
    }
  }

  Widget _buildSyncStatusTile(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStatusProvider);
    final isSignedIn = authAsync.valueOrNull ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        isSignedIn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        color: isSignedIn ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: const Text('Google Drive'),
      subtitle: Text(
        isSignedIn ? 'Signed in' : 'Not signed in',
        style: TextStyle(
          color: isSignedIn ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSyncDialog(context, ref),
    );
  }

  void _showSyncDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _SyncBottomSheet(),
    ).whenComplete(() {
      ref.invalidate(authStatusProvider);
    });
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

class _SyncBottomSheet extends ConsumerStatefulWidget {
  const _SyncBottomSheet();

  @override
  ConsumerState<_SyncBottomSheet> createState() => _SyncBottomSheetState();
}

class _SyncBottomSheetState extends ConsumerState<_SyncBottomSheet> {
  bool _isLoading = false;
  String? _lastSyncTime;
  bool _isSignedIn = false;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadLastSyncTime();
    _loadAuthState();
  }

  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(AppConstants.prefLastSyncTime);
    if (mounted) {
      setState(() => _lastSyncTime = lastSync);
    }
  }

  Future<void> _loadAuthState() async {
    final syncService = getIt<SyncService>();
    final signedIn = await syncService.isSignedIn();
    String? email;
    if (signedIn) {
      final user = syncService.currentUser ?? await syncService.signInSilently();
      email = user?.email;
    }
    if (mounted) {
      setState(() {
        _isSignedIn = signedIn;
        _userEmail = email;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Google Drive Sync',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (_isSignedIn && _userEmail != null) ...[
              const SizedBox(height: 4),
              Text(
                'Signed in as: $_userEmail',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            if (_lastSyncTime != null) ...[
              Text(
                'Last sync: ${_lastSyncTime!.substring(0, 16).replaceFirst('T', ' ')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _isLoading ? null : _performSync,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload),
              label: Text(_isLoading ? 'Syncing...' : 'Upload Sync Data'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _restoreBackup,
              icon: const Icon(Icons.download),
              label: const Text('Restore from Google Drive'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            if (!_isSignedIn) ...[
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign in to Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ] else ...[
              TextButton.icon(
                onPressed: _isLoading ? null : _signOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _performSync() async {
    setState(() => _isLoading = true);
    try {
      final syncService = getIt<SyncService>();
      final isSignedIn = await syncService.isSignedIn();
      if (!isSignedIn) {
        final account = await syncService.signIn();
        if (account == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google Sign-In cancelled')),
            );
          }
          return;
        }
        if (mounted) {
          setState(() {
            _isSignedIn = true;
            _userEmail = account.email;
          });
        }
      }

      final db = getIt<DatabaseHelper>();

      // Pre-check connectivity so we can show a helpful message when Wi-Fi Only blocks sync
      final shouldSync = await syncService.shouldSync();
      if (!shouldSync) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sync skipped: Wi-Fi Only is enabled. Connect to Wi-Fi or disable Wi-Fi Only Sync in Settings.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final success = await syncService.uploadBackup(db);

      if (!mounted) return;
      if (success) {
        await _loadLastSyncTime();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync failed. Check your Google Sign-In or network connection.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() => _isLoading = true);
    try {
      final syncService = getIt<SyncService>();
      final isSignedIn = await syncService.isSignedIn();
      if (!isSignedIn) {
        final account = await syncService.signIn();
        if (account == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google Sign-In cancelled')),
            );
          }
          return;
        }
        if (mounted) {
          setState(() {
            _isSignedIn = true;
            _userEmail = account.email;
          });
        }
      }

      final backupData = await syncService.downloadBackup();
      if (!mounted) return;

      if (backupData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No backup found on Google Drive')),
        );
        return;
      }

      final db = getIt<DatabaseHelper>();
      final exportService = ExportService(db);
      final jsonString = jsonEncode(backupData);
      final success = await exportService.importFromJson(jsonString);

      if (!mounted) return;
      if (success) {
        // Refresh all providers to reload the UI with the restored data
        ref.read(taskActionsProvider).refreshAllTaskProviders();
        ref.invalidate(allTaskLogsProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to restore backup')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final syncService = getIt<SyncService>();
      final account = await syncService.signIn();
      if (!mounted) return;
      if (account != null) {
        setState(() {
          _isSignedIn = true;
          _userEmail = account.email;
        });
        ref.invalidate(authStatusProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signed in as ${account.email}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-In cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-In error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    try {
      final syncService = getIt<SyncService>();
      await syncService.signOut();
      if (!mounted) return;
      setState(() {
        _isSignedIn = false;
        _userEmail = null;
      });
      ref.invalidate(authStatusProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed out')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-Out error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _QuietHoursResult {
  final TimeOfDay start;
  final TimeOfDay end;
  _QuietHoursResult(this.start, this.end);
}

class _QuietHoursDialog extends StatefulWidget {
  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;

  const _QuietHoursDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  State<_QuietHoursDialog> createState() => _QuietHoursDialogState();
}

class _QuietHoursDialogState extends State<_QuietHoursDialog> {
  late TimeOfDay _start;
  late TimeOfDay _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quiet Hours'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Start Time'),
            trailing: Text(_start.format(context)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _start,
              );
              if (picked != null) {
                setState(() => _start = picked);
              }
            },
          ),
          ListTile(
            title: const Text('End Time'),
            trailing: Text(_end.format(context)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _end,
              );
              if (picked != null) {
                setState(() => _end = picked);
              }
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
          onPressed: () => Navigator.pop(
            context,
            _QuietHoursResult(_start, _end),
          ),
          child: const Text('Save'),
        ),
      ],
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
