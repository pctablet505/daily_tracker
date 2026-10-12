import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notifications.dart';
import 'providers.dart';

/// Refreshes the screens when something outside the app's own code wrote to the
/// database (a notification's Done button). Watch it once, near the root.
final externalChangesProvider = Provider<void>((ref) {
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(dataChangedPortName);
  IsolateNameServer.registerPortWithName(port.sendPort, dataChangedPortName);
  final sub = port.listen((_) {
    if (ref.mounted) ref.read(revisionProvider.notifier).bump();
  });
  ref.onDispose(() {
    sub.cancel();
    port.close();
    IsolateNameServer.removePortNameMapping(dataChangedPortName);
  });
});
