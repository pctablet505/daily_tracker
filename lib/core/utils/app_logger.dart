import 'package:flutter/foundation.dart';

/// Simple, privacy-aware logger.
///
/// Messages are only emitted in debug builds. No release logging means
/// sensitive data (tokens, emails, file contents) never leaves the app
/// through log streams.
class AppLogger {
  AppLogger._();

  static void d(String message) {
    if (kDebugMode) {
      debugPrint('[DailyTracker] $message');
    }
  }

  static void e(String message, [Object? error]) {
    if (kDebugMode) {
      debugPrint(
          '[DailyTracker] ERROR: $message${error != null ? ' | $error' : ''}');
    }
  }
}
