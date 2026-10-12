import 'dart:ui' show IsolateNameServer;

import 'package:daily_tracker/services/notifications.dart';
import 'package:daily_tracker/state/external_changes.dart';
import 'package:daily_tracker/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a change announced by a notification button refreshes the screens',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(externalChangesProvider);
      final before = container.read(revisionProvider);

      announceDataChanged();
      await pumpEventQueue();

      expect(container.read(revisionProvider), before + 1);
    },
  );

  test('stops listening when the app is torn down', () async {
    final container = ProviderContainer();
    container.read(externalChangesProvider);
    expect(IsolateNameServer.lookupPortByName(dataChangedPortName), isNotNull);

    container.dispose();

    expect(IsolateNameServer.lookupPortByName(dataChangedPortName), isNull);
  });

  test('announcing with nobody listening does nothing', () {
    expect(IsolateNameServer.lookupPortByName(dataChangedPortName), isNull);
    expect(announceDataChanged, returnsNormally);
  });
}
