import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../features/update/update_dialog.dart';

final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  // Only check on Android
  if (!Platform.isAndroid) return null;

  final service = UpdateService();
  final update = await service.checkForUpdate();
  return update;
});

final pendingUpdateProvider = StateNotifierProvider<PendingUpdateNotifier, UpdateInfo?>((ref) {
  return PendingUpdateNotifier();
});

class PendingUpdateNotifier extends StateNotifier<UpdateInfo?> {
  PendingUpdateNotifier() : super(null) {
    _loadPendingUpdate();
  }

  Future<void> _loadPendingUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString(AppConstants.prefPendingUpdateVersion);
    final url = prefs.getString(AppConstants.prefPendingUpdateUrl);
    final changelog = prefs.getString(AppConstants.prefPendingUpdateChangelog);

    if (version != null && url != null) {
      state = UpdateInfo(
        version: version,
        changelog: changelog ?? '',
        downloadUrl: url,
      );
    }
  }

  Future<void> setPendingUpdate(UpdateInfo update) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefPendingUpdateVersion, update.version);
    await prefs.setString(AppConstants.prefPendingUpdateUrl, update.downloadUrl);
    await prefs.setString(AppConstants.prefPendingUpdateChangelog, update.changelog);
    state = update;
  }

  Future<void> clearPendingUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefPendingUpdateVersion);
    await prefs.remove(AppConstants.prefPendingUpdateUrl);
    await prefs.remove(AppConstants.prefPendingUpdateChangelog);
    state = null;
  }
}
