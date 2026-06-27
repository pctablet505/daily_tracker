/// Safe parsing helpers for data coming from SQLite, JSON, or external sources.
///
/// These helpers centralize null/typo handling so models don't throw on
/// corrupted or partially-migrated rows. They return sensible defaults and
/// log nothing by design (no debugPrint in production parsing paths).
class SafeParse {
  SafeParse._();

  /// Parses a boolean stored as an int (1 = true, 0 = false) or bool.
  static bool boolean(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      return lower == '1' || lower == 'true' || lower == 'yes';
    }
    return defaultValue;
  }

  /// Parses an int, returning [defaultValue] on any failure.
  static int integer(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value.trim()) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Parses a double, returning [defaultValue] on any failure.
  static double float(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim()) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Returns a non-null string, defaulting to [defaultValue].
  static String string(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }

  /// Returns a nullable string (empty strings are preserved).
  static String? stringNullable(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  /// Parses an ISO-8601 date string safely.
  static DateTime? dateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Parses an ISO-8601 date string, falling back to [defaultValue].
  static DateTime dateTimeOrNow(dynamic value, {DateTime? defaultValue}) {
    return dateTime(value) ?? defaultValue ?? DateTime.now();
  }
}
