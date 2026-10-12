import 'package:daily_tracker/services/updater.dart';
import 'package:daily_tracker/state/update_prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const release = ReleaseInfo(
  version: '2.1.0',
  notes: 'n',
  apkUrl: 'https://x/a.apk',
);

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  late UpdateCheck result;
  late int checks;
  late bool wifi;
  late bool online;

  UpdatePrompter make({bool wifiOnly = false}) => UpdatePrompter(
    prefs: prefs,
    now: () => now,
    check: () async {
      checks++;
      return result;
    },
    isOnWifi: () async => wifi,
    isOnline: () async => online,
    wifiOnly: () => wifiOnly,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 11, 12);
    result = const UpdateAvailable(release);
    checks = 0;
    wifi = true;
    online = true;
  });

  test('offers a new release', () async {
    expect((await make().releaseToOffer())?.version, '2.1.0');
  });

  test('asks GitHub at most about twice a day', () async {
    final p = make();
    await p.releaseToOffer();
    now = now.add(const Duration(hours: 5));
    await p.releaseToOffer();
    expect(checks, 1);
    now = now.add(const Duration(hours: 8));
    await p.releaseToOffer();
    expect(checks, 2);
  });

  test(
    'does not nag: the same version is offered again only after three days',
    () async {
      final p = make();
      expect(await p.releaseToOffer(), isNotNull);
      now = now.add(const Duration(days: 1));
      expect(await p.releaseToOffer(), isNull);
      now = now.add(const Duration(days: 3));
      expect(await p.releaseToOffer(), isNotNull);
    },
  );

  test(
    'a newer version is offered at once even if the older one was just offered',
    () async {
      final p = make();
      await p.releaseToOffer();
      now = now.add(const Duration(days: 1));
      result = const UpdateAvailable(
        ReleaseInfo(version: '2.2.0', notes: 'n', apkUrl: 'u'),
      );
      expect((await p.releaseToOffer())?.version, '2.2.0');
    },
  );

  test('nothing to offer when up to date or when the check failed', () async {
    result = const UpToDate();
    expect(await make().releaseToOffer(), isNull);
    now = now.add(const Duration(days: 1));
    result = const UpdateCheckFailed('x');
    expect(await make().releaseToOffer(), isNull);
  });

  test('a failed check is tried again sooner than a good one', () async {
    result = const UpdateCheckFailed('offline');
    final p = make();
    await p.releaseToOffer();
    now = now.add(const Duration(hours: 2));
    result = const UpdateAvailable(release);
    expect(await p.releaseToOffer(), isNotNull);
  });

  test('offline: does not even ask', () async {
    online = false;
    expect(await make().releaseToOffer(), isNull);
    expect(checks, 0);
  });

  test('on mobile data with Wi-Fi only on: does not even ask', () async {
    wifi = false;
    expect(await make(wifiOnly: true).releaseToOffer(), isNull);
    expect(checks, 0);
    expect(await make().releaseToOffer(), isNotNull);
  });

  test('the user can say "skip this version"', () async {
    final p = make();
    await p.skip('2.1.0');
    expect(await p.releaseToOffer(), isNull);
    now = now.add(const Duration(days: 30));
    expect(await p.releaseToOffer(), isNull);
    now = now.add(const Duration(hours: 13));
    result = const UpdateAvailable(
      ReleaseInfo(version: '2.2.0', notes: 'n', apkUrl: 'u'),
    );
    expect((await p.releaseToOffer())?.version, '2.2.0');
  });
}
