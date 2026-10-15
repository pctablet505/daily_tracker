import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What leaves the phone through Android's backup and phone-to-phone transfer. The settings
/// file also holds the app-lock PIN's hash and the Drive sign-in, so it must stay out of
/// every rule, and the comments must describe what the rules really do.
String _xml(String name) =>
    File('android/app/src/main/res/xml/$name').readAsStringSync();

String _withoutComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

String _comments(String xml) => RegExp(
  r'<!--(.*?)-->',
  dotAll: true,
).allMatches(xml).map((m) => m[1]!).join('\n');

String _block(String xml, String tag) {
  final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
  expect(m, isNotNull, reason: 'no <$tag> section');
  return m![1]!;
}

void main() {
  final extraction = _xml('data_extraction_rules.xml');
  final legacy = _xml('backup_rules.xml');

  test('the settings file is in no backup or transfer rule', () {
    for (final xml in [extraction, legacy]) {
      expect(_withoutComments(xml), isNot(contains('sharedpref')));
    }
  });

  test('cloud backup carries the database only', () {
    final cloud = _block(_withoutComments(extraction), 'cloud-backup');
    expect(cloud, contains('domain="database"'));
    expect(cloud, isNot(contains('domain="file"')));
    expect(_withoutComments(legacy), contains('domain="database"'));
    expect(_withoutComments(legacy), isNot(contains('domain="file"')));
  });

  test('a phone-to-phone transfer carries the database and the photos', () {
    final transfer = _block(_withoutComments(extraction), 'device-transfer');
    expect(transfer, contains('domain="database"'));
    expect(transfer, contains('domain="file" path="media"'));
  });

  test('the comment does not claim a transfer keeps everything', () {
    final c = _comments(extraction)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(c, isNot(contains('keeps everything')));
    expect(
      c,
      contains('settings'),
      reason: 'say what a transfer leaves behind',
    );
    expect(c, contains('pin'));
  });
}
