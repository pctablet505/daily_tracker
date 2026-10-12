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

  test('access to the user\'s photos, music and videos is removed from the merged manifest', () {
    for (final permission in [
      'READ_EXTERNAL_STORAGE',
      'READ_MEDIA_IMAGES',
      'READ_MEDIA_VIDEO',
      'READ_MEDIA_AUDIO',
    ]) {
      expect(
        RegExp('android\\.permission\\.$permission"\\s+tools:node="remove"')
            .hasMatch(manifest),
        isTrue,
        reason: permission,
      );
    }
  });

  group('Android backup rules', () {
    final cloud = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync()
        .split('<device-transfer>')
        .first;
    final old = File('android/app/src/main/res/xml/backup_rules.xml')
        .readAsStringSync();

    test('the cloud copy holds the database and nothing else', () {
      expect(cloud, contains('domain="database"'));
      expect(cloud, isNot(contains('sharedpref')));
      expect(cloud, isNot(contains('domain="file"')));
    });

    test('so does the automatic backup of Android 11 and older', () {
      expect(old, contains('domain="database"'));
      expect(old, isNot(contains('sharedpref')));
    });
  });

  test('MainActivity is a FragmentActivity so fingerprint unlock can open its dialog', () {
    final activity = File(
      'android/app/src/main/kotlin/com/dailytracker/daily_tracker/MainActivity.kt',
    ).readAsStringSync();
    expect(
      activity,
      contains('import io.flutter.embedding.android.FlutterFragmentActivity'),
    );
    expect(activity, contains('class MainActivity: FlutterFragmentActivity()'));
  });
}
