import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/day_key.dart';
import '../data/repository.dart';
import '../state/actions.dart';
import '../state/providers.dart';

enum PhotoSource { camera, gallery }

/// Asks the user for a photo and returns the picked file's path, or null if
/// they backed out. [habitId] and [day] say what the photo is for, so it can
/// still be logged if Android stops the app meanwhile (see [recoverLostPhoto]).
typedef PhotoPicker = Future<String?> Function(
  PhotoSource source, {
  String? habitId,
  DayKey? day,
});

const _pendingKey = 'photo.pendingFor';

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

/// Wraps [pick] so the habit and day stay on record while the camera or
/// gallery is open. Android may stop the app behind it, and then nothing
/// but this record says what the photo was for.
PhotoPicker rememberingTarget(
  SharedPreferences prefs,
  Future<String?> Function(PhotoSource source) pick,
) => (source, {habitId, day}) async {
  final remember = habitId != null && day != null;
  if (remember) await prefs.setString(_pendingKey, '$habitId@$day');
  try {
    return await pick(source);
  } finally {
    if (remember) await prefs.remove(_pendingKey);
  }
};

/// The photo Android kept when it stopped the app while the picker was open.
Future<String?> lostImagePickerPhoto() async {
  final lost = await ImagePicker().retrieveLostData();
  return lost.isEmpty ? null : lost.file?.path;
}

/// Logs a photo whose pick outlived the app, for the habit and day it was
/// taken for, the same way a returned pick is logged. Never throws.
Future<void> recoverLostPhoto(
  SharedPreferences prefs, {
  required Future<String?> Function() lostPhoto,
  required HabitRepository repo,
  required HabitActions actions,
}) async {
  final pending = prefs.getString(_pendingKey);
  if (pending == null) return;
  try {
    final path = await lostPhoto();
    final at = pending.lastIndexOf('@');
    final day = DayKey.tryParse(pending.substring(at + 1));
    if (path == null || at < 1 || day == null) return;
    final id = pending.substring(0, at);
    final habit = (await repo.habits()).where((h) => h.id == id).firstOrNull;
    if (habit != null) await actions.logPhoto(habit, day, path);
  } catch (e) {
    debugPrint('Could not log the photo taken before the app stopped: $e');
  } finally {
    await prefs.remove(_pendingKey);
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) =>
      rememberingTarget(ref.watch(sharedPrefsProvider), _pickWithImagePicker),
);
