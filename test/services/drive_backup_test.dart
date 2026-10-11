import 'package:daily_tracker/services/drive_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_drive.dart';

void main() {
  late FakeDrive drive;
  late FakeAuth auth;
  late DriveBackup backup;

  setUp(() {
    drive = FakeDrive();
    auth = FakeAuth();
    backup = DriveBackup(auth, MockClient(drive.handle));
  });

  test('nothing is there before the first upload', () async {
    expect(await backup.info(), isNull);
    expect(await backup.download(), isNull);
  });

  test(
    'the first upload creates the file, a later one updates the same file',
    () async {
      await backup.upload('{"v":1}');
      expect(drive.files.length, 1);
      await backup.upload('{"v":2}');
      expect(drive.files.length, 1);
      expect(await backup.download(), '{"v":2}');
    },
  );

  test('upload reports the stored size and time', () async {
    final info = await backup.upload('{"v":1}');
    expect(info.size, 7);
    expect(info.modified, DateTime.utc(2026, 10, 11, 12));
    expect((await backup.info())!.size, 7);
  });

  test('unicode survives the round trip', () async {
    await backup.upload('{"note":"café — 日本語 ✓"}');
    expect(await backup.download(), '{"note":"café — 日本語 ✓"}');
  });

  test('when several files carry the name, the newest is used', () async {
    drive.files['old'] = (
      name: driveFileName,
      content: 'OLD',
      modified: DateTime.utc(2026, 1, 1),
    );
    drive.files['new'] = (
      name: driveFileName,
      content: 'NEW',
      modified: DateTime.utc(2026, 6, 1),
    );
    expect(await backup.download(), 'NEW');
  });

  test('a backup in the Drive trash is not used', () async {
    drive.files['gone'] = (
      name: driveFileName,
      content: 'TRASHED',
      modified: DateTime.utc(2026, 9, 1),
    );
    drive.trashed.add('gone');
    expect(await backup.download(), isNull);
    await backup.upload('{"v":1}');
    expect(drive.files['gone']!.content, 'TRASHED');
    expect(await backup.download(), '{"v":1}');
  });

  test('other files in the folder are left alone', () async {
    drive.files['x'] = (
      name: 'something-else.json',
      content: 'X',
      modified: DateTime.utc(2026, 1, 1),
    );
    await backup.upload('{}');
    expect(drive.files['x']!.content, 'X');
    expect(drive.files.length, 2);
  });

  group('failures say what to do', () {
    test('not signed in', () async {
      auth.signedIn = false;
      await expectLater(
        backup.upload('{}'),
        throwsA(
          isA<DriveException>().having(
            (e) => e.needsSignIn,
            'needsSignIn',
            true,
          ),
        ),
      );
    });

    test('Google refusing the token (401) asks to sign in again', () async {
      drive.failWith = 401;
      await expectLater(
        backup.info(),
        throwsA(
          isA<DriveException>().having(
            (e) => e.needsSignIn,
            'needsSignIn',
            true,
          ),
        ),
      );
    });

    test('Drive being full or unavailable gives a readable message', () async {
      drive.failWith = 403;
      await expectLater(
        backup.upload('{}'),
        throwsA(
          isA<DriveException>()
              .having((e) => e.message, 'message', contains('full'))
              .having((e) => e.needsSignIn, 'needsSignIn', false),
        ),
      );
      drive.failWith = 503;
      await expectLater(backup.download(), throwsA(isA<DriveException>()));
    });

    test('a lost connection is an error, not a silent success', () async {
      final b = DriveBackup(
        auth,
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        b.upload('{}'),
        throwsA(
          isA<DriveException>().having(
            (e) => e.message,
            'message',
            contains('connection'),
          ),
        ),
      );
    });
  });
}
