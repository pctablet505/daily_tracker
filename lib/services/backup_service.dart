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
/// Spreadsheets skip leading spaces, so a formula behind them counts too.
final _formula = RegExp(r'^([\t\r\n]|\s*[=+\-@])');

String _safeCell(String s) => _formula.hasMatch(s) ? "'$s" : s;

String csvRow(List<String> cells) => cells
    .map((c) {
      final s = _safeCell(c);
      return s.contains(RegExp('[,"\r\n]'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    })
    .join(',');

String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
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
    this._sweepPhotos,
  });

  final HabitRepository repo;
  final Settings Function() _readSettings;
  final Future<void> Function(Map<String, Object>) _applySettings;
  final Future<Directory> Function() _safetyDir;
  final DateTime Function() _now;
  final Future<String> Function() _appVersion;

  /// Removes the photos nothing refers to once a restore is done.
  final Future<void> Function()? _sweepPhotos;

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
  /// Then photos that neither the data nor a safety copy refers to are removed.
  Future<void> restore(String text) async {
    final backup = decodeBackup(text);
    await _saveSafetyCopy();
    await repo.replaceAll(backup.snapshot);
    await _applySettings(backup.settings);
    await _sweepPhotos?.call();
  }

  static final _numbered = RegExp(r'-n(\d+)\.json$');

  static int? _number(File f) {
    final m = _numbered.firstMatch(p.basename(f.path));
    return m == null ? null : int.tryParse(m[1]!);
  }

  /// The copies made before restores, newest first. Each copy is numbered one
  /// above the copies before it, so the order never depends on the phone's
  /// clock, which may have been wrong once. Copies from versions that did not
  /// number them are older than any numbered one, and go by when they were written.
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
      final (na, nb) = (_number(a), _number(b));
      if (na != null || nb != null) return (nb ?? -1).compareTo(na ?? -1);
      final byTime = when(b).compareTo(when(a));
      return byTime != 0
          ? byTime
          : p.basename(b.path).compareTo(p.basename(a.path));
    });
    return copies;
  }

  /// The photo names the copies made before restores refer to, so their
  /// photos stay for "Undo the last restore". Null when a copy cannot be read,
  /// since then which photos it needs is unknown.
  Future<Set<String>?> photosInSafetyCopies() async {
    try {
      return {
        for (final copy in await _safetyCopies())
          for (final e in decodeBackup(
            await copy.readAsString(),
          ).snapshot.entries)
            if (e.photoPath != null) e.photoPath!,
      };
    } catch (_) {
      return null;
    }
  }

  /// Whether there is a copy of what was here before a restore.
  Future<bool> hasSafetyCopy() async => (await _safetyCopies()).isNotEmpty;

  /// The newest safety copy, checked. A damaged one is refused rather than
  /// passed over: an older copy would quietly put back the wrong data. Throws
  /// [FormatException] with a message fit to show.
  Future<String> _lastSafetyCopy() async {
    final copies = await _safetyCopies();
    if (copies.isEmpty)
      throw const FormatException('There is nothing to undo.');
    try {
      final text = await copies.first.readAsString();
      decodeBackup(text);
      return text;
    } on Exception {
      throw const FormatException(
        'The copy from before the last restore is damaged, so it cannot be put back. Nothing was changed.',
      );
    }
  }

  /// What [undoLastRestore] would put back, for the confirmation step. Throws
  /// [FormatException] as [undoLastRestore] does.
  Future<BackupPreview> lastRestorePreview() async =>
      preview(await _lastSafetyCopy());

  /// Puts back what was on the phone before the last restore. That itself saves
  /// a copy first, so undoing twice goes back and forth.
  Future<void> undoLastRestore() async => restore(await _lastSafetyCopy());

  Future<void> _saveSafetyCopy() async {
    final dir = await _safetyDir();
    await dir.create(recursive: true);
    final stamp = _now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final copies = await _safetyCopies();
    final number = (copies.isEmpty ? 0 : _number(copies.first) ?? 0) + 1;
    final written = File(
      p.join(dir.path, 'before-restore-$stamp-n$number.json'),
    );
    final tmp = File('${written.path}.tmp');
    await tmp.writeAsString(await _encode(), flush: true);
    await tmp.rename(written.path);
    for (final old in (await _safetyCopies()).skip(_keepSafetyCopies)) {
      await old.delete();
    }
  }
}
