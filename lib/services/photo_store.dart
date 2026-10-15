import 'dart:io';

import 'package:path/path.dart' as p;

/// Where progress photos live. Entries keep only a file name; the file is in
/// the app's own folder, so it survives the camera or gallery cache being cleared.
abstract interface class PhotoStore {
  /// Copies the picked file into the store and returns the stored file name.
  Future<String> importFile(String sourcePath);

  /// The file for a stored [name]. It may not exist (for example after a
  /// restore onto a new phone, since backups do not carry photos).
  File fileFor(String name);

  /// Whether the photo for [name] is on the phone. Never throws. Cheap enough
  /// to call for every row on each rebuild.
  bool exists(String name);

  /// Removes a stored photo; a name that is already gone is fine.
  Future<void> delete(String name);
}

final class DiskPhotoStore implements PhotoStore {
  DiskPhotoStore(this.directory, {String Function()? newId})
    : _newId = newId ?? _timeId;

  final Directory directory;
  final String Function() _newId;

  /// What [exists] found, so a rebuild does not stat every photo again. Photos
  /// only come and go through this store.
  final _exists = <String, bool>{};

  static int _n = 0;
  static String _timeId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_n++).toRadixString(36)}';

  @override
  Future<String> importFile(String sourcePath) async {
    await directory.create(recursive: true);
    var ext = p.extension(sourcePath).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) ext = '.jpg';
    final name = '${_newId()}$ext';
    await File(sourcePath).copy(p.join(directory.path, name));
    _exists[name] = true;
    return name;
  }

  @override
  File fileFor(String name) {
    if (name != p.basename(name) ||
        name.trim().isEmpty ||
        name != name.trim() ||
        name.startsWith('.') ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains(':')) {
      throw ArgumentError.value(
        name,
        'name',
        'not a file name inside the photo folder',
      );
    }
    return File(p.join(directory.path, name));
  }

  @override
  bool exists(String name) => _exists.putIfAbsent(name, () {
    try {
      return fileFor(name).existsSync();
    } on ArgumentError {
      return false;
    }
  });

  @override
  Future<void> delete(String name) async {
    final f = fileFor(name);
    if (await f.exists()) await f.delete();
    _exists[name] = false;
  }
}
