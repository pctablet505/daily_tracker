import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/update/update_dialog.dart';

final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  // Only check on Android
  if (!Platform.isAndroid) return null;

  final service = UpdateService();
  final update = await service.checkForUpdate();
  return update;
});
