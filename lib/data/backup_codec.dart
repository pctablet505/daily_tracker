import 'dart:convert';

import '../core/day_key.dart';
import '../logic/habit_form.dart';
import 'models.dart';
import 'repository.dart';

const backupFormat = 'daily-tracker-backup';
const backupVersion = 1;

/// No phone dates a day before this; an earlier day in a backup is damage, and
/// would send every streak count back through the centuries.

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
  if (version < 1) {
    throw const FormatException('The backup file is damaged.');
  }
  if (version > backupVersion) {
    throw const FormatException(
      'This backup was made by a newer version of the app. Update the app and try again.',
    );
  }
  const damaged = FormatException('The backup file is damaged.');
  try {
    final habits = [
      for (final m in _list(root['habits']))
        _withinFormLimits(Habit.fromMap(_map(m))),
    ];
    final entries = [
      for (final m in _list(root['entries'])) Entry.fromMap(_map(m)),
    ];
    final seen = {
      for (final d in _list(root['seenDays'] ?? const <Object?>[]))
        DayKey.parse(d! as String),
    };
    // A habit's end needs no check of its own: fromMap holds it to no earlier
    // than the day before the start.
    if (habits.any((h) => h.createdDay < earliestDay) ||
        entries.any((e) => e.day < earliestDay) ||
        seen.any((d) => d < earliestDay)) {
      throw damaged;
    }
    final snapshot = Snapshot(habits: habits, entries: entries, seenDays: seen)
      ..validate();
    final exported = root['exportedAt'];
    if (exported != null && exported is! String) throw damaged;
    final exportedAt = exported is String ? DateTime.tryParse(exported) : null;
    if (exported is String && exportedAt == null) throw damaged;
    final app = root['app'];
    if (app != null && app is! String) throw damaged;
    return BackupData(
      snapshot: snapshot,
      settings: _settings(root['settings']),
      exportedAt:
          exportedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion: app as String?,
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

/// An older version let in values the form no longer allows. They are brought
/// within its limits rather than refused, so such a backup still restores.
Habit _withinFormLimits(Habit h) {
  String? text(String? v, int max) =>
      v == null || v.trim().isEmpty ? null : _cut(v.trim(), max);
  final goal = h.goal;
  return h.copyWith(
    name: _cut(h.name.trim(), HabitForm.maxNameLength),
    description: () => text(h.description, HabitForm.maxDescriptionLength),
    unit: () => text(h.unit, HabitForm.maxUnitLength),
    area: () => text(h.area, HabitForm.maxAreaLength),
    goal: () => goal == null
        ? null
        : (goal.clamp(0.01, HabitForm.maxGoal) * 100).roundToDouble() / 100,
  );
}

String _cut(String text, int max) {
  if (text.length <= max) return text;
  // Never keep the first half of a two-unit character such as an emoji.
  final cut = text.codeUnitAt(max - 1) & 0xFC00 == 0xD800 ? max - 1 : max;
  return text.substring(0, cut).trimRight();
}

List<Object?> _list(Object? v) => v as List<Object?>;
Map<String, Object?> _map(Object? v) => v! as Map<String, Object?>;

Map<String, Object> _settings(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map<String, Object?>) {
    throw const FormatException('The backup file is damaged.');
  }
  return {
    for (final e in raw.entries)
      if (e.value is bool ||
          (e.value is num && (e.value! as num).isFinite) ||
          e.value is String)
        e.key: e.value!,
  };
}
