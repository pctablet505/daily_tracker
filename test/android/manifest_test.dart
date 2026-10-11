import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The notification plugin only works if the app declares its receivers; a
/// missing one fails silently on the phone (no reminder is ever shown), and no
/// other test can see it.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  for (final receiver in [
    'ScheduledNotificationReceiver',
    'ScheduledNotificationBootReceiver',
    'ActionBroadcastReceiver',
  ]) {
    test('the manifest declares $receiver', () {
      expect(
        manifest,
        contains(
          'android:name="com.dexterous.flutterlocalnotifications.$receiver"',
        ),
      );
    });
  }

  test('the boot receiver listens for a reboot, so reminders survive one', () {
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
  });

  test('only the notification permission is asked for, not exact alarms', () {
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
  });
}
