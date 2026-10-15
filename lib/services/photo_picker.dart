import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// Asks the user for a photo and returns the picked file's path, or null if they backed out.
typedef PhotoPicker = Future<String?> Function(PhotoSource source);

Future<String?> _pickWithImagePicker(PhotoSource source) async {
  final file = await ImagePicker().pickImage(
    source: source == PhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 85,
  );
  return file?.path;
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => _pickWithImagePicker,
);
