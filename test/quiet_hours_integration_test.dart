import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_tracker/core/constants/app_constants.dart';
import 'package:daily_tracker/services/notification/quiet_hours_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final store = <String, Object>{};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getAll':
        case 'getAllWithParameters':
          return Map<String, Object>.from(store);
        case 'setString':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as String;
          return true;
        case 'setBool':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as bool;
          return true;
        case 'setInt':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as int;
          return true;
        case 'setDouble':
          final args = call.arguments as Map<dynamic, dynamic>;
          store[args['key'] as String] = args['value'] as double;
          return true;
        case 'remove':
          final args = call.arguments as Map<dynamic, dynamic>;
          store.remove(args['key'] as String);
          return true;
        case 'clear':
          store.clear();
          return true;
        case 'clearWithParameters':
          final args = call.arguments as Map<dynamic, dynamic>;
          final prefix = args['prefix'] as String? ?? '';
          store.removeWhere((key, _) => key.startsWith(prefix));
          return true;
        default:
          return null;
      }
    });
  });

  setUp(() async {
    store.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('QuietHoursService.isInQuietHours', () {
    final service = QuietHoursService();

    Future<void> setQuietHours(String start, String end) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefQuietHoursStart, start);
      await prefs.setString(AppConstants.prefQuietHoursEnd, end);
    }

    test('returns false when no quiet hours are configured', () async {
      expect(
        await service.isInQuietHours(DateTime(2024, 6, 15, 23, 30)),
        isFalse,
      );
    });

    test('cross-day range 22:00-07:00 treats overnight hours as quiet',
        () async {
      await setQuietHours('22:00', '07:00');

      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 23, 0)), isTrue);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 22, 0)), isTrue);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 16, 6, 59)), isTrue);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 16, 7, 0)), isFalse);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 21, 59)), isFalse);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 16, 12, 0)), isFalse);
    });

    test('same-day range 09:00-17:00 treats daytime hours as quiet', () async {
      await setQuietHours('09:00', '17:00');

      expect(await service.isInQuietHours(DateTime(2024, 6, 15, 9, 0)), isTrue);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 16, 59)), isTrue);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 8, 59)), isFalse);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 17, 0)), isFalse);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 0, 0)), isFalse);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 23, 59)), isFalse);
    });

    test('time exactly at boundary follows half-open interval semantics',
        () async {
      await setQuietHours('22:00', '07:00');

      // Start is inclusive, end is exclusive.
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 22, 0)), isTrue);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 16, 7, 0)), isFalse);

      await setQuietHours('09:00', '17:00');

      expect(await service.isInQuietHours(DateTime(2024, 6, 15, 9, 0)), isTrue);
      expect(
          await service.isInQuietHours(DateTime(2024, 6, 15, 17, 0)), isFalse);
    });

    test('malformed time strings fall back to false', () async {
      final times = [
        DateTime(2024, 6, 15, 23, 0),
        DateTime(2024, 6, 15, 3, 0),
        DateTime(2024, 6, 15, 12, 0),
      ];

      await setQuietHours('not-a-time', '07:00');
      for (final time in times) {
        expect(await service.isInQuietHours(time), isFalse);
      }

      await setQuietHours('22:00', '25:00');
      for (final time in times) {
        expect(await service.isInQuietHours(time), isFalse);
      }

      await setQuietHours('2200', '0700');
      for (final time in times) {
        expect(await service.isInQuietHours(time), isFalse);
      }

      await setQuietHours('', '');
      for (final time in times) {
        expect(await service.isInQuietHours(time), isFalse);
      }
    });
  });

  group('QuietHoursService.adjustForQuietHours', () {
    final service = QuietHoursService();

    Future<void> setQuietHours(String start, String end) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefQuietHoursStart, start);
      await prefs.setString(AppConstants.prefQuietHoursEnd, end);
    }

    test('returns scheduled time unchanged when not in quiet hours', () async {
      final scheduled = DateTime(2024, 6, 15, 12, 0, 30, 123, 456);
      final adjusted = await service.adjustForQuietHours(scheduled);
      expect(adjusted, equals(scheduled));
    });

    test('cross-day quiet hours pushes time to end on the next day', () async {
      await setQuietHours('22:00', '07:00');
      final scheduled = DateTime(2024, 6, 15, 23, 30, 15, 500);
      final adjusted = await service.adjustForQuietHours(scheduled);

      expect(adjusted, equals(DateTime(2024, 6, 16, 7, 0, 15, 500)));
    });

    test('same-day quiet hours pushes time to end on the same day', () async {
      await setQuietHours('09:00', '17:00');
      final scheduled = DateTime(2024, 6, 15, 10, 30, 45, 250);
      final adjusted = await service.adjustForQuietHours(scheduled);

      expect(adjusted, equals(DateTime(2024, 6, 15, 17, 0, 45, 250)));
    });

    test('scheduled time exactly at quiet-hours end is not adjusted', () async {
      await setQuietHours('09:00', '17:00');
      final scheduled = DateTime(2024, 6, 15, 17, 0, 0, 0);
      final adjusted = await service.adjustForQuietHours(scheduled);

      expect(adjusted, equals(scheduled));
    });

    test('malformed or missing quiet hours leave scheduled time unchanged',
        () async {
      final scheduled = DateTime(2024, 6, 15, 23, 30);

      expect(await service.adjustForQuietHours(scheduled), equals(scheduled));

      await setQuietHours('bad', 'worse');
      expect(await service.adjustForQuietHours(scheduled), equals(scheduled));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefQuietHoursStart, '22:00');
      // Missing end key.
      await prefs.remove(AppConstants.prefQuietHoursEnd);
      expect(await service.adjustForQuietHours(scheduled), equals(scheduled));
    });

    test('preserves sub-minute precision across day rollover', () async {
      await setQuietHours('22:00', '07:00');
      final scheduled = DateTime(2024, 6, 15, 23, 59, 59, 999, 999);
      final adjusted = await service.adjustForQuietHours(scheduled);

      expect(adjusted.year, equals(2024));
      expect(adjusted.month, equals(6));
      expect(adjusted.day, equals(16));
      expect(adjusted.hour, equals(7));
      expect(adjusted.minute, equals(0));
      expect(adjusted.second, equals(59));
      expect(adjusted.millisecond, equals(999));
      expect(adjusted.microsecond, equals(999));
    });
  });
}
