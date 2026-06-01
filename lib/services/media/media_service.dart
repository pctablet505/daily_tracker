import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class MediaService {
  static Future<String?> pickAndSaveImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      if (file.path == null) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${appDir.path}/media');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      // Sanitize extension to prevent path traversal
      var ext = path.extension(file.path!).toLowerCase();
      if (!['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext)) {
        ext = '.jpg';
      }

      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}$ext';
      final targetPath = path.join(mediaDir.path, fileName);

      // Verify target path is within media directory (path traversal protection)
      if (!path.isWithin(mediaDir.path, targetPath)) {
        return null;
      }

      final savedFile = await File(file.path!).copy(targetPath);
      return savedFile.path;
    } catch (e) {
      return null;
    }
  }

  static Future<void> cleanupUnusedMedia(List<String> activePaths) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${appDir.path}/media');
      if (!await mediaDir.exists()) return;

      final List<FileSystemEntity> files = await mediaDir.list().toList();
      final Set<String> activeSet = activePaths.map((p) => path.normalize(p)).toSet();

      for (final file in files) {
        if (file is File) {
          final normalizedPath = path.normalize(file.path);
          // Only delete files that are within the media directory
          if (path.isWithin(mediaDir.path, normalizedPath) &&
              !activeSet.contains(normalizedPath)) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      // Ignore or log error
    }
  }
}
