import 'dart:convert';
import 'dart:io';

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

final class SystemFileService implements FileService {
  @override
  Future<String?> pickAndReadText({int maxBytes = 20 * 1024 * 1024}) async {
    final f = await FilePicker.pickFile();
    if (f == null) return null;
    final length = await f.length();
    if (length != null && length > maxBytes)
      throw const FormatException('That file is too large.');
    final bytes = await f.readAsBytes();
    return utf8.decode(bytes);
  }

  @override
  Future<void> shareText(
    String fileName,
    String content, {
    String? subject,
    String mimeType = 'application/json',
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }
}

final fileServiceProvider = Provider<FileService>((ref) => SystemFileService());
