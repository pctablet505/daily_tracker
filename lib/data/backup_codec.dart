import 'dart:convert';

import '../core/day_key.dart';
import 'models.dart';
import 'repository.dart';

const backupFormat = 'daily-tracker-backup';
const backupVersion = 1;

/// What a backup file holds once read.
final class BackupData {
  const BackupData({
    required this.snapshot,
    required this.settings,
    required this.exportedAt,
    required this.appVersion,
  });

  final Snapshot snapshot;

  /// Plain settings values (numbers, text, true/false) by name.
  final Map<String, Object> settings;
  final DateTime exportedAt;
  final String? appVersion;
}

/// Writes the backup as readable JSON. Photos are not included: entries keep
/// the photo's file name, and the file itself stays on the device.
String encodeBackup(
  Snapshot snapshot, {
  Map<String, Object> settings = const {},
  required DateTime now,
  required String appVersion,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': backupFormat,
    'version': backupVersion,
    'exportedAt': now.toUtc().toIso8601String(),
    'app': appVersion,
    'habits': [for (final h in snapshot.habits) h.toMap()],
    'entries': [for (final e in snapshot.entries) e.toMap()],
    'seenDays': [
      for (final d in snapshot.seenDays.toList()..sort()) d.toString(),
    ],
    'settings': settings,
  });
}

/// Reads a backup. Throws [FormatException] with a message fit to show the
/// user when the file is not one of ours, is from a newer version, or is damaged.
BackupData decodeBackup(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This is not a Daily Tracker backup.');
  }
  if (root is! Map<String, Object?> || root['format'] != backupFormat) {
    throw const FormatException('This is not a Daily Tracker backup.');
  }
  final version = root['version'];
  if (version is! int)
    throw const FormatException('The backup has no version number.');
  if (version > backupVersion) {
    throw const FormatException(
      'This backup was made by a newer version of the app. Update the app and try again.',
    );
  }
  const damaged = FormatException('The backup file is damaged.');
  try {
    final habits = [
      for (final m in _list(root['habits'])) Habit.fromMap(_map(m)),
    ];
    final entries = [
      for (final m in _list(root['entries'])) Entry.fromMap(_map(m)),
    ];
    final seen = {
      for (final d in _list(root['seenDays'] ?? const <Object?>[]))
        DayKey.parse(d! as String),
    };
    final snapshot = Snapshot(habits: habits, entries: entries, seenDays: seen)
      ..validate();
    final exported = root['exportedAt'];
    return BackupData(
      snapshot: snapshot,
      settings: _settings(root['settings']),
      exportedAt:
          (exported is String ? DateTime.tryParse(exported) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion: root['app'] as String?,
    );
  } on TypeError {
    throw damaged;
  } on FormatException catch (e) {
    // validate() explains an entry without a habit; anything else is damage.
    if (e.message.contains('habit') && e.message.contains('not in the data')) {
      throw const FormatException(
        'An entry in the backup belongs to a habit that is not in it.',
      );
    }
    throw damaged;
  }
}

List<Object?> _list(Object? v) => v as List<Object?>;
Map<String, Object?> _map(Object? v) => v! as Map<String, Object?>;

Map<String, Object> _settings(Object? raw) {
  if (raw is! Map<String, Object?>) return const {};
  return {
    for (final e in raw.entries)
      if (e.value is bool || e.value is num || e.value is String)
        e.key: e.value!,
  };
}
