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
    s.isNotEmpty && '=+-@\t\r\n'.contains(s[0]) ? "'$s" : s;

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
      final h = byId[e.habitId];
      if (h == null) continue;
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

  /// The copies made before restores, newest first. The order comes from when
  /// each was written, not from its name: a phone clock that was wrong once
  /// must not make an old copy look new.
  Future<List<File>> _safetyCopies() async {
    final dir = await _safetyDir();
    if (!dir.existsSync()) return [];
    final copies = dir
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              p.basename(f.path).startsWith('before-restore-') &&
              f.path.endsWith('.json'),
        )
        .toList();
    DateTime when(File f) => f.statSync().modified;
    copies.sort((a, b) {
      final byTime = when(b).compareTo(when(a));
      return byTime != 0
          ? byTime
          : p.basename(b.path).compareTo(p.basename(a.path));
    });
    return copies;
  }

  /// Whether there is a copy of what was here before a restore.
  Future<bool> hasSafetyCopy() async => (await _safetyCopies()).isNotEmpty;

  /// Puts back what was on the phone before the last restore. That itself saves
  /// a copy first, so undoing twice goes back and forth.
  Future<void> undoLastRestore() async {
    final copies = await _safetyCopies();
    if (copies.isEmpty)
      throw const FormatException('There is nothing to undo.');
    for (final copy in copies) {
      final text = await copy.readAsString();
      try {
        decodeBackup(text);
      } on FormatException {
        continue;
      }
      await restore(text);
      return;
    }
    throw const FormatException('The safety copy is damaged.');
  }

  Future<void> _saveSafetyCopy() async {
    final dir = await _safetyDir();
    await dir.create(recursive: true);
    final stamp = _now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final written = File(p.join(dir.path, 'before-restore-$stamp.json'));
    final tmp = File('${written.path}.tmp');
    await tmp.writeAsString(await _encode(), flush: true);
    await tmp.rename(written.path);
    // Keep the copy just made, plus the newest of the others.
    final others = (await _safetyCopies()).where((f) => f.path != written.path);
    for (final old in others.skip(_keepSafetyCopies - 1)) {
      await old.delete();
    }
  }
}
