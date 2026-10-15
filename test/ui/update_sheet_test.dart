import 'dart:io';

import 'package:daily_tracker/services/updater.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/ui/sheets/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Downloads to a real file (unless [keepFile] is off) and answers installs
/// from [installResults]: a message, null for success, or an error to throw.
final class _FakeUpdates extends UpdateService {
  _FakeUpdates(this.installResults, {this.downloadError});
  final List<Object?> installResults;
  final UpdateException? downloadError;
  int downloads = 0;
  int installs = 0;
  late final Directory dir = Directory.systemTemp.createTempSync('dt_update_');

  @override
  Future<File> download(
    ReleaseInfo r, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancel,
  }) async {
    downloads++;
    if (downloadError case final e?) throw e;
    return File('${dir.path}/daily-tracker-${r.version}.apk')
      ..writeAsStringSync('apk');
  }

  @override
  Future<String?> install(File apk) async {
    final result = installResults[installs++];
    if (result is Exception) throw result;
    return result as String?;
  }
}

void main() {
  setUpAll(loadAppFont);

  const release = ReleaseInfo(
    version: '9.0.0',
    notes: 'Line\nLine\nLine\nLine\nLine\nLine',
    apkUrl: 'https://example.test/a.apk',
    apkSize: 25000000,
  );

  Future<void> openSheet(
    WidgetTester tester,
    _FakeUpdates fake, {
    double textScale = 1,
    Size size = const Size(360, 780),
  }) async {
    addTearDown(() => fake.dir.deleteSync(recursive: true));
    final overrides = await baseOverrides()
      ..add(updateServiceProvider.overrideWithValue(fake));
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showUpdateSheet(context, release, onSkip: () async {}),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      overrides: overrides,
      textScale: textScale,
      size: size,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download and install'));
    await tester.pumpAndSettle();
  }

  testWidgets('a successful second install attempt clears the old error', (
    tester,
  ) async {
    final fake = _FakeUpdates(['Could not open the installer.', null]);
    await openSheet(tester, fake);
    expect(find.text('Could not open the installer.'), findsOneWidget);

    await tester.tap(find.text('Try installing again'));
    await tester.pumpAndSettle();
    expect(fake.installs, 2);
    expect(find.text('Could not open the installer.'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('a downloaded file that is gone is downloaded again', (
    tester,
  ) async {
    final fake = _FakeUpdates(['Could not open the installer.', null]);
    await openSheet(tester, fake);
    for (final f in fake.dir.listSync()) {
      f.deleteSync();
    }

    await tester.tap(find.text('Try installing again'));
    await tester.pumpAndSettle();
    expect((fake.downloads, fake.installs), (2, 2));
  });

  testWidgets(
    'an installer that fails to open is not called a failed download',
    (tester) async {
      final fake = _FakeUpdates([Exception('no activity')]);
      await openSheet(tester, fake);
      expect(find.text('The download failed.'), findsNothing);
      expect(find.text('Could not open the installer.'), findsOneWidget);
      expect(find.text('Try installing again'), findsOneWidget);
    },
  );

  testWidgets('the error state fits at 2x text on 360x640', (tester) async {
    final fake = _FakeUpdates(
      const [],
      downloadError: const UpdateException(
        'The download timed out. Check your connection and try again.',
      ),
    );
    final errors = await collectFrameworkErrors(
      () => openSheet(tester, fake, textScale: 2, size: const Size(360, 640)),
    );
    expect(errors, isEmpty);
    await tester.scrollUntilVisible(
      find.text('Skip this version'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Skip this version').hitTestable(), findsOneWidget);
  });
}
