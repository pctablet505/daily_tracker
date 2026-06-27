import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/services/background/background_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'be.tramckrijte.workmanager/foreground_channel_work_manager',
  );
  final calls = <MethodCall>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  setUp(() {
    calls.clear();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('BackgroundService registers WorkManager tasks', () {
    test(
      'registerUpdateCheck uses 24h frequency, connected network, '
      'battery not low, and update policy',
      () async {
        await BackgroundService.registerUpdateCheck();

        final periodicCalls =
            calls.where((c) => c.method == 'registerPeriodicTask').toList();
        expect(periodicCalls, hasLength(1));

        final args = periodicCalls.first.arguments as Map<dynamic, dynamic>;
        expect(args['isInDebugMode'], isFalse);
        expect(args['uniqueName'], 'update-check');
        expect(args['taskName'], 'dailyTrackerUpdateCheck');
        expect(args['frequency'], const Duration(hours: 24).inSeconds);
        expect(args['existingWorkPolicy'], 'update');
        expect(args['networkType'], 'connected');
        expect(args['requiresBatteryNotLow'], isTrue);
      },
    );

    test(
      'registerAutoSync uses 6h frequency, unmetered network, '
      'battery not low, and update policy',
      () async {
        await BackgroundService.registerAutoSync();

        final periodicCalls =
            calls.where((c) => c.method == 'registerPeriodicTask').toList();
        expect(periodicCalls, hasLength(1));

        final args = periodicCalls.first.arguments as Map<dynamic, dynamic>;
        expect(args['isInDebugMode'], isFalse);
        expect(args['uniqueName'], 'auto-sync');
        expect(args['taskName'], 'dailyTrackerAutoSync');
        expect(args['frequency'], const Duration(hours: 6).inSeconds);
        expect(args['existingWorkPolicy'], 'update');
        expect(args['networkType'], 'unmetered');
        expect(args['requiresBatteryNotLow'], isTrue);
      },
    );

    test(
      'registerDailyReset uses 24h frequency, no network constraint, '
      'and update policy with a positive initial delay',
      () async {
        await BackgroundService.registerDailyReset();

        final periodicCalls =
            calls.where((c) => c.method == 'registerPeriodicTask').toList();
        expect(periodicCalls, hasLength(1));

        final args = periodicCalls.first.arguments as Map<dynamic, dynamic>;
        expect(args['isInDebugMode'], isFalse);
        expect(args['uniqueName'], 'daily-reset');
        expect(args['taskName'], 'dailyTrackerReset');
        expect(args['frequency'], const Duration(hours: 24).inSeconds);
        expect(args['existingWorkPolicy'], 'update');
        expect(args['networkType'], 'not_required');
        expect(args['requiresBatteryNotLow'], isFalse);
        expect(args['requiresCharging'], isFalse);
        expect(args['initialDelaySeconds'], greaterThan(0));
      },
    );

    test('cancelAll invokes cancelAllTasks', () async {
      await BackgroundService.cancelAll();

      expect(
        calls.map((c) => c.method),
        contains('cancelAllTasks'),
      );
    });
  });
}
