class AppConstants {
  static const String appName = 'Daily Tracker';
  static const String appVersion = '1.0.0';
  static const String databaseName = 'daily_tracker.db';
  static const String databaseVersion = '1';

  // GitHub Update Config
  static const String githubOwner = 'pctablet505';
  static const String githubRepo = 'daily_tracker';
  static const String apkAssetPrefix = 'app-github';

  // Sync
  static const String syncFileName = 'daily_tracker_backup.enc';
  static const String syncManifestName = 'manifest.json';

  // Preferences Keys
  static const String prefFirstLaunch = 'first_launch';
  static const String prefDarkMode = 'dark_mode';
  static const String prefUseMaterialYou = 'use_material_you';
  static const String prefAppLockEnabled = 'app_lock_enabled';
  static const String prefAppLockPin = 'app_lock_pin';
  static const String prefBiometricEnabled = 'biometric_enabled';
  static const String prefQuietHoursStart = 'quiet_hours_start';
  static const String prefQuietHoursEnd = 'quiet_hours_end';
  static const String prefNotificationsEnabled = 'notifications_enabled';
  static const String prefAutoSync = 'auto_sync_enabled';
  static const String prefWifiOnlyUpdates = 'wifi_only_updates';
  static const String prefWifiOnlySync = 'wifi_only_sync';
  static const String prefLastSyncTime = 'last_sync_time';
  static const String prefPendingUpdateVersion = 'pending_update_version';
  static const String prefPendingUpdateUrl = 'pending_update_url';
  static const String prefPendingUpdateChangelog = 'pending_update_changelog';
  static const String prefStreakCount = 'streak_count';
  static const String prefLastStreakDate = 'last_streak_date';

  // Notification Channels
  static const String channelTaskReminders = 'task_reminders';
  static const String channelDailySummary = 'daily_summary';

  // Default Values
  static const int defaultReminderIdStart = 1000;
}
