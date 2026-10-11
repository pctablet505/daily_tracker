import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/backup_codec.dart';
import '../data/repository.dart';
import '../state/settings.dart';

/// What a backup file holds, for the confirmation screen.
final class BackupPreview {
  const BackupPreview({
    required this.habits,
    required this.entries,
    required this.exportedAt,
    required this.appVersion,
  });
  final int habits;
  final int entries;
  final DateTime exportedAt;
  final String? appVersion;
}

final class ExportedFile {
  const ExportedFile(this.fileName, this.text);
  final String fileName;
  final String text;
}

/// A cell a spreadsheet might run as a formula gets a leading apostrophe.
String _safeCell(String s) =>
    s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;

String csvRow(List<String> cells) => cells
    .map((c) {
      final s = _safeCell(c);
      return s.contains(RegExp('[,"\r\n]'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    })
    .join(',');

String _date(DateTime d) {
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
}

/// Export, preview and restore of the local backup file.
class BackupService {
  BackupService({
    required this.repo,
    required this._readSettings,
    required this._applySettings,
    required this._safetyDir,
    required this._now,
    required this._appVersion,
  });

  final HabitRepository repo;
  final Settings Function() _readSettings;
  final Future<void> Function(Map<String, Object>) _applySettings;
  final Future<Directory> Function() _safetyDir;
  final DateTime Function() _now;
  final Future<String> Function() _appVersion;

  static const _keepSafetyCopies = 3;

  Future<String> _encode() async => encodeBackup(
    await repo.snapshot(),
    settings: _readSettings().exportMap(),
    now: _now(),
    appVersion: await _appVersion(),
  );

  Future<ExportedFile> export() async => ExportedFile(
    'daily-tracker-backup-${_date(_now())}.json',
    await _encode(),
  );

  /// The backup as JSON text, for uploading elsewhere.
  Future<String> encodeForUpload() => _encode();

  Future<ExportedFile> exportCsv() async {
    final snap = await repo.snapshot();
    final byId = {for (final h in snap.habits) h.id: h};
    final rows = <String>[
      csvRow(['habit', 'kind', 'day', 'state', 'value', 'note']),
    ];
    for (final e in snap.entries) {
      final h = byId[e.habitId]!;
      rows.add(
        csvRow([
          h.name,
          h.kind.name,
          e.day.toString(),
          e.state.name,
          e.value?.toString() ?? '',
          e.note ?? '',
        ]),
      );
    }
    return ExportedFile(
      'daily-tracker-entries-${_date(_now())}.csv',
      '${rows.join('\r\n')}\r\n',
    );
  }

  /// Reads [text] without changing anything. Throws [FormatException] with a readable message.
  BackupPreview preview(String text) {
    final b = decodeBackup(text);
    return BackupPreview(
      habits: b.snapshot.habits.length,
      entries: b.snapshot.entries.length,
      exportedAt: b.exportedAt,
      appVersion: b.appVersion,
    );
  }

  /// Replaces everything with the backup in [text]. The current data is saved
  /// to a safety file first, and nothing is touched if the file is not valid.
  Future<void> restore(String text) async {
    final backup = decodeBackup(text);
    await _saveSafetyCopy();
    await repo.replaceAll(backup.snapshot);
    await _applySettings(backup.settings);
  }

  Future<void> _saveSafetyCopy() async {
    final dir = await _safetyDir();
    await dir.create(recursive: true);
    final stamp = _now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    await File(p.join(dir.path, 'before-restore-$stamp.json'))
        .writeAsString(await _encode());
    final copies =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith('before-restore-'))
            .toList()
          ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final old in copies.skip(_keepSafetyCopies)) {
      await old.delete();
    }
  }
}
