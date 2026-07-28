import 'package:test/test.dart';

import '../../scripts/src/check_updates.dart';
import '../../scripts/src/common.dart';

void main() {
  group('validateUpstreamTag', () {
    test('accepts the upstream tag form, with or without the v prefix', () {
      expect(validateUpstreamTag('0.16.0'), '0.16.0');
      expect(validateUpstreamTag('v0.16.0'), 'v0.16.0');
      expect(validateUpstreamTag('1.0.0'), '1.0.0');
      expect(validateUpstreamTag('10.20.30'), '10.20.30');
    });

    test('accepts semver prerelease identifiers', () {
      // liboqs ships release candidates (e.g. 0.15.0-rc1) and the checker has to
      // recognise them to report is_prerelease rather than reject the release.
      expect(validateUpstreamTag('0.17.0-rc1'), '0.17.0-rc1');
      expect(validateUpstreamTag('0.17.0-rc.1'), '0.17.0-rc.1');
    });

    test('accepts the version recorded in pubspec.yaml', () {
      // liboqs.native_version is compared, exported and written back by the
      // checker, so the shape it must satisfy is the same one validated here.
      expect(() => validateUpstreamTag(getLiboqsVersion()), returnsNormally);
    });

    test('rejects shell metacharacters', () {
      // The value is interpolated into `make check ARGS=...` and reaches a
      // recipe shell, so anything that could terminate the command must fail.
      for (final tag in <String>[
        '0.16.0; rm -rf /',
        '0.16.0\$(whoami)',
        '0.16.0`id`',
        '0.16.0 --force',
        '0.16.0 && echo pwned',
        '0.16.0 | tee /tmp/x',
      ]) {
        expect(
          () => validateUpstreamTag(tag),
          throwsFormatException,
          reason: 'must reject: $tag',
        );
      }
    });

    test('rejects newline injection, including a bare trailing newline', () {
      // A newline would forge a second `key=value` line in GITHUB_OUTPUT.
      expect(
        () => validateUpstreamTag('0.16.0\nneeds_update=false'),
        throwsFormatException,
      );
      expect(() => validateUpstreamTag('0.16.0\n'), throwsFormatException);
    });

    test('rejects path traversal', () {
      // The value becomes part of a branch name and a release URL.
      expect(
        () => validateUpstreamTag('../../etc/passwd'),
        throwsFormatException,
      );
      expect(
        () => validateUpstreamTag('0.16.0/../evil'),
        throwsFormatException,
      );
    });

    test('rejects non-canonical numeric segments', () {
      expect(() => validateUpstreamTag('0.016.0'), throwsFormatException);
      expect(() => validateUpstreamTag('0.16'), throwsFormatException);
      expect(() => validateUpstreamTag('0.16.0.1'), throwsFormatException);
      expect(() => validateUpstreamTag(''), throwsFormatException);
    });

    test('names the rejected source in the message', () {
      // The three call sites (API response, --version argument, pubspec) fail
      // for different reasons; the message has to say which one to look at.
      expect(
        () => validateUpstreamTag('nope', source: '--version argument'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('--version argument'),
          ),
        ),
      );
    });
  });
}
