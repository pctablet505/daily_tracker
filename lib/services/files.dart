import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Picking files to read and handing files to the user. A fake replaces it in tests.
abstract interface class FileService {
  /// Lets the user pick a file and returns its text, or null if they backed out.
  /// Throws a [FormatException] if the file is larger than [maxBytes].
  Future<String?> pickAndReadText({int maxBytes = 20 * 1024 * 1024});

  /// Writes [content] to a file named [fileName] in the app's temp folder and
  /// opens the share sheet for it, so the user can save or send it.
  Future<void> shareText(
    String fileName,
    String content, {
    String? subject,
    String mimeType = 'application/json',
  });
}

/// What the picker hands back, reduced to what is read from it.
abstract interface class PickedFile {
  Future<int?> length();
  Stream<List<int>> readAsByteStream();
}

final class _PlatformPicked implements PickedFile {
  _PlatformPicked(this._file);
  final PlatformFile _file;

  @override
  Future<int?> length() => _file.length();

  @override
  Stream<List<int>> readAsByteStream() => _file.readAsByteStream();
}

/// The picker and the share sheet leave copies of the user's backup in the app's cache,
/// and a backup holds their habits and notes. Picked copies are cleared once the file is
/// read. Shared copies sit in their own folder, and the share plugin makes one more in its
/// own `share_plus` folder that it only clears at the next share; both are removed once
/// they are old, because the receiving app may still be reading a fresh one.
final class SystemFileService implements FileService {
  SystemFileService({
    Future<Directory> Function()? tempDir,
    Future<void> Function(ShareParams)? share,
    Future<PickedFile?> Function()? pick,
    Future<void> Function()? clearPicked,
  }) : _tempDir = tempDir ?? getTemporaryDirectory,
       _share = share ?? ((params) => SharePlus.instance.share(params)),
       _pick = pick ?? _pickWithPlugin,
       _clearPicked = clearPicked ?? FilePicker.clearTemporaryFiles;

  static const sharedFolder = 'shared';

  /// Where the share plugin keeps its own copy of whatever is shared.
  static const pluginShareFolder = 'share_plus';

  static const shareKeepFor = Duration(hours: 1);

  final Future<Directory> Function() _tempDir;
  final Future<void> Function(ShareParams) _share;
  final Future<PickedFile?> Function() _pick;
  final Future<void> Function() _clearPicked;

  static Future<PickedFile?> _pickWithPlugin() async {
    final f = await FilePicker.pickFile();
    return f == null ? null : _PlatformPicked(f);
  }

  /// Removes shared copies that are older than [shareKeepFor]. Safe to call any time.
  Future<void> clearOldShares() async {
    final temp = (await _tempDir()).path;
    for (final folder in [sharedFolder, pluginShareFolder]) {
      try {
        await _removeOldShares(Directory(p.join(temp, folder)));
      } on FileSystemException {
        // Nothing to clean, or it is busy: the next share tries again.
      }
    }
  }

  Future<void> _removeOldShares(Directory dir) async {
    if (!await dir.exists()) return;
    final cutoff = DateTime.now().subtract(shareKeepFor);
    await for (final e in dir.list()) {
      if (e is! File) continue;
      try {
        if ((await e.lastModified()).isBefore(cutoff)) await e.delete();
      } on FileSystemException {
        // Gone already, or in use: leave it for next time.
      }
    }
  }

  Future<void> _clearPickedCopies() async {
    try {
      await _clearPicked();
    } catch (_) {
      // Only a tidy-up: it must never lose the text that was read.
    }
  }

  @override
  Future<String?> pickAndReadText({int maxBytes = 20 * 1024 * 1024}) async {
    final f = await _pick();
    if (f == null) return null;
    try {
      final length = await f.length();
      if (length != null && length > maxBytes)
        throw const FormatException('That file is too large.');
      // The picker may not know the size, so stop reading once it is too large
      // instead of holding the whole file first.
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in f.readAsByteStream()) {
        bytes.add(chunk);
        if (bytes.length > maxBytes)
          throw const FormatException('That file is too large.');
      }
      try {
        return utf8.decode(bytes.takeBytes());
      } on FormatException {
        throw const FormatException('That file is not a readable text file.');
      }
    } finally {
      await _clearPickedCopies();
    }
  }

  @override
  Future<void> shareText(
    String fileName,
    String content, {
    String? subject,
    String mimeType = 'application/json',
  }) async {
    final dir = Directory(p.join((await _tempDir()).path, sharedFolder));
    await dir.create(recursive: true);
    await clearOldShares();
    final file = File(p.join(dir.path, p.basename(fileName)));
    await file.writeAsString(content);
    await _share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }
}

final fileServiceProvider = Provider<FileService>((ref) => SystemFileService());
