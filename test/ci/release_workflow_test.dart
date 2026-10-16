import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The workflow only really runs on GitHub; these read it as text so a change
/// that hands pull requests a write token, or drops a release check, is caught here.
void main() {
  final workflow = File('.github/workflows/build-release.yml')
      .readAsStringSync();
  final buildAt = workflow.indexOf('\n  build:\n');
  final releaseAt = workflow.indexOf('\n  release:\n');
  final build = workflow.substring(
    buildAt,
    releaseAt < 0 ? workflow.length : releaseAt,
  );
  final release = releaseAt < 0 ? '' : workflow.substring(releaseAt);

  test(
    'the build job (which runs pull requests) only reads the repository',
    () {
      expect(buildAt, isNot(-1));
      expect(build, contains('contents: read'));
      expect(build, isNot(contains('contents: write')));
      expect(build, contains('persist-credentials: false'));
      expect(build, isNot(contains('action-gh-release')));
    },
  );

  test('the build job keeps the release checks', () {
    expect(build, contains(r'"$pub" != "${GITHUB_REF_NAME#v}"'));
    expect(build, contains('Check the signing secrets exist'));
    expect(build, contains('tool/check_apk_abis.sh'));
    expect(build, contains('actions/upload-artifact'));
  });

  test('a separate job publishes, after the build, on tag pushes only', () {
    expect(release, contains('needs: build'));
    expect(
      release,
      contains(
        "if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/')",
      ),
    );
    expect(release, contains('contents: write'));
    expect(release, contains('actions/download-artifact'));
    expect(release, contains('name: release-apk'));
    expect(release, contains('softprops/action-gh-release'));
  });
}
