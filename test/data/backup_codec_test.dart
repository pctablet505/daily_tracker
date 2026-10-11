import 'dart:convert';

import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Snapshot sample() => Snapshot(
  habits: [
    habit('a', area: 'Health', logType: LogType.number, goal: 8),
    stayClear('s').copyWith(sortOrder: 1, endDay: () => fri),
  ],
  entries: [
    entry('a', mon, EntryState.partial, 3),
    Entry(
      habitId: 'a',
      day: tue,
      state: EntryState.done,
      note: 'good',
      photoPath: 'p1.jpg',
      loggedAt: DateTime.utc(2026, 10, 6, 8),
    ),
    slip('s', wed),
  ],
  seenDays: {mon, tue, wed},
);

Map<String, Object?> decoded(String json) =>
    jsonDecode(json) as Map<String, Object?>;

void main() {
  final when = DateTime.utc(2026, 10, 11, 14, 30);

  test('a backup decodes to exactly what was encoded', () {
    final text = encodeBackup(
      sample(),
      settings: {'streakThreshold': 60, 'theme': 'dark'},
      now: when,
      appVersion: '2.0.0',
    );
    final back = decodeBackup(text);
    final s = sample();
    expect(back.snapshot.habits, s.habits);
    expect(back.snapshot.entries, s.entries);
    expect(back.snapshot.seenDays, s.seenDays);
    expect(back.settings, {'streakThreshold': 60, 'theme': 'dark'});
    expect(back.exportedAt, when);
    expect(back.appVersion, '2.0.0');
  });

  test('says what it is and which format version it uses', () {
    final m = decoded(encodeBackup(sample(), now: when, appVersion: '2.0.0'));
    expect(m['format'], 'daily-tracker-backup');
    expect(m['version'], 1);
    expect(m['exportedAt'], '2026-10-11T14:30:00.000Z');
  });

  test('the export time is written in UTC even when given a local time', () {
    final m = decoded(
      encodeBackup(sample(), now: when.toLocal(), appVersion: '2.0.0'),
    );
    expect(m['exportedAt'], '2026-10-11T14:30:00.000Z');
  });

  test('keeps the photo file name but never any photo bytes', () {
    final text = encodeBackup(sample(), now: when, appVersion: '2.0.0');
    expect(text.contains('p1.jpg'), isTrue);
    expect(decodeBackup(text).snapshot.entries[1].photoPath, 'p1.jpg');
  });

  test('is readable JSON with a stable layout', () {
    final text = encodeBackup(sample(), now: when, appVersion: '2.0.0');
    expect(text.contains('\n'), isTrue);
    expect(text, encodeBackup(sample(), now: when, appVersion: '2.0.0'));
  });

  test('an empty app exports and imports as empty', () {
    final text = encodeBackup(
      const Snapshot(habits: [], entries: [], seenDays: {}),
      now: when,
      appVersion: '2.0.0',
    );
    final back = decodeBackup(text);
    expect(back.snapshot.habits, isEmpty);
    expect(back.snapshot.entries, isEmpty);
    expect(back.snapshot.seenDays, isEmpty);
    expect(back.settings, isEmpty);
  });

  test('settings that are not plain values are dropped, not trusted', () {
    final m = decoded(encodeBackup(sample(), now: when, appVersion: '2.0.0'));
    m['settings'] = {
      'ok': 1,
      'flag': true,
      'name': 'x',
      'ratio': 0.5,
      'nested': {'a': 1},
      'list': [1],
      'nothing': null,
    };
    expect(decodeBackup(jsonEncode(m)).settings, {
      'ok': 1,
      'flag': true,
      'name': 'x',
      'ratio': 0.5,
    });
  });

  test('a missing settings section is fine', () {
    final m = decoded(encodeBackup(sample(), now: when, appVersion: '2.0.0'))
      ..remove('settings');
    expect(decodeBackup(jsonEncode(m)).settings, isEmpty);
  });

  test('fields this version does not know are ignored', () {
    final m = decoded(encodeBackup(sample(), now: when, appVersion: '2.0.0'))
      ..['somethingNew'] = 1;
    (m['habits']! as List<Object?>).cast<Map<String, Object?>>().first['mood'] =
        'x';
    expect(decodeBackup(jsonEncode(m)).snapshot.habits.length, 2);
  });

  group('is refused with a readable message when', () {
    void refused(String why, String text, Pattern message) {
      test(why, () {
        expect(
          () => decodeBackup(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              matches(message),
            ),
          ),
        );
      });
    }

    Map<String, Object?> good() =>
        decoded(encodeBackup(sample(), now: when, appVersion: '2.0.0'));

    refused('it is not JSON', 'hello', 'not a Daily Tracker backup');
    refused(
      'it is JSON but not an object',
      '[1,2]',
      'not a Daily Tracker backup',
    );
    refused(
      'it is some other JSON file',
      '{"a":1}',
      'not a Daily Tracker backup',
    );
    refused('it is empty', '', 'not a Daily Tracker backup');
    refused(
      'it comes from a newer version',
      jsonEncode(good()..['version'] = 2),
      'newer version',
    );
    refused(
      'the version is missing',
      jsonEncode(good()..remove('version')),
      'version',
    );
    refused(
      'the habits are not a list',
      jsonEncode(good()..['habits'] = 'x'),
      'damaged',
    );
    refused(
      'the entries are missing',
      jsonEncode(good()..remove('entries')),
      'damaged',
    );
    refused(
      'a habit has a field of the wrong type',
      jsonEncode(
        good()
          ..['habits'] = [
            {'id': 5, 'name': 'x', 'createdDay': '2026-10-05'},
          ],
      ),
      'damaged',
    );
    refused(
      'an entry has a field of the wrong type',
      jsonEncode(
        good()
          ..['entries'] = [
            {'habitId': 'a', 'day': '2026-10-05', 'value': 'lots'},
          ],
      ),
      'damaged',
    );
    refused(
      'an entry names a habit that is not in the file',
      jsonEncode(
        good()
          ..['entries'] = [
            {'habitId': 'zzz', 'day': '2026-10-05', 'state': 'done'},
          ],
      ),
      'habit',
    );
    refused(
      'a seen day is not a date',
      jsonEncode(good()..['seenDays'] = ['yesterday']),
      'damaged',
    );
    refused(
      'a habit has an impossible date',
      jsonEncode(
        good()
          ..['habits'] = [
            {'id': 'a', 'name': 'x', 'createdDay': '2026-02-30'},
          ],
      ),
      'damaged',
    );
  });
}
