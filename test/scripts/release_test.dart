import 'package:test/test.dart';

import '../../scripts/src/release.dart';
import '../../scripts/src/update_changelog.dart';

/// A CHANGELOG shaped like the real one: an `[Unreleased]` section with
/// in-progress content, two released sections, and compare links at the bottom.
const _changelog = '''
## [Unreleased]

### For Users

#### ✨ Highlights

- **liboqs 0.17.0** — maintenance update, no algorithm changes

#### Changed

- Update bundled liboqs native library to 0.17.0

## [2.0.0] - 2026-07-13

### For Users

- Bundled liboqs upgraded 0.15.0 → 0.16.0

## [1.2.1] - 2026-05-14

- Older release

[Unreleased]: https://github.com/djx-y-z/liboqs_dart/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.2.1...v2.0.0
[1.2.1]: https://github.com/djx-y-z/liboqs_dart/compare/v1.2.0...v1.2.1
''';

const _repoUrl = 'https://github.com/djx-y-z/liboqs_dart';

/// Index of the line that starts with [prefix]; -1 if none.
int _lineStarting(String content, String prefix) =>
    content.split('\n').indexWhere((l) => l.startsWith(prefix));

void main() {
  group('finalizeChangelog', () {
    test('renames [Unreleased] to the dated version heading', () {
      final result = finalizeChangelog(
        _changelog,
        version: '2.1.0',
        date: '2026-08-01',
      );
      expect(result, contains('## [2.1.0] - 2026-08-01'));
    });

    test('leaves a fresh empty [Unreleased] above the new version', () {
      final result = finalizeChangelog(
        _changelog,
        version: '2.1.0',
        date: '2026-08-01',
      );

      // Exactly one Unreleased heading remains.
      expect('## [Unreleased]'.allMatches(result).length, equals(1));

      final lines = result.split('\n');
      final unreleasedIdx = lines.indexWhere(
        (l) => l.startsWith('## [Unreleased]'),
      );
      final versionIdx = lines.indexWhere((l) => l.startsWith('## [2.1.0]'));
      // Unreleased comes first and is empty (only blank lines up to [2.1.0]).
      expect(unreleasedIdx, lessThan(versionIdx));
      final between = lines
          .sublist(unreleasedIdx + 1, versionIdx)
          .where((l) => l.trim().isNotEmpty);
      expect(between, isEmpty, reason: 'the new [Unreleased] must be empty');
    });

    test('moves in-progress content under the released heading', () {
      final result = finalizeChangelog(
        _changelog,
        version: '2.1.0',
        date: '2026-08-01',
      );
      final lines = result.split('\n');
      final versionIdx = lines.indexWhere((l) => l.startsWith('## [2.1.0]'));
      final prevIdx = lines.indexWhere((l) => l.startsWith('## [2.0.0]'));
      final highlightIdx = lines.indexWhere(
        (l) => l.contains('**liboqs 0.17.0**'),
      );
      // The formerly-unreleased highlight now sits inside the [2.1.0] section.
      expect(highlightIdx, greaterThan(versionIdx));
      expect(highlightIdx, lessThan(prevIdx));
    });

    test('rewrites the [Unreleased] compare link to the new version', () {
      final result = finalizeChangelog(
        _changelog,
        version: '2.1.0',
        date: '2026-08-01',
      );
      expect(result, contains('[Unreleased]: $_repoUrl/compare/v2.1.0...HEAD'));
      expect(
        result,
        isNot(contains('/compare/v2.0.0...HEAD')),
        reason: 'the old Unreleased range must be replaced',
      );
    });

    test('inserts the new version compare link spanning previous...new', () {
      final result = finalizeChangelog(
        _changelog,
        version: '2.1.0',
        date: '2026-08-01',
      );
      expect(result, contains('[2.1.0]: $_repoUrl/compare/v2.0.0...v2.1.0'));
      // The new link sits directly under the Unreleased link.
      final unreleasedLinkIdx = _lineStarting(result, '[Unreleased]:');
      final newLinkIdx = _lineStarting(result, '[2.1.0]:');
      expect(newLinkIdx, equals(unreleasedLinkIdx + 1));
    });

    test('derives the base URL and previous version from the link, not a '
        'hardcoded slug', () {
      const forked = '''
## [Unreleased]

- pending

## [2.0.0] - 2026-01-01

- prior

[Unreleased]: https://example.com/acme/widget/compare/v2.0.0...HEAD
[2.0.0]: https://example.com/acme/widget/compare/v1.9.0...v2.0.0
''';
      final result = finalizeChangelog(
        forked,
        version: '2.1.0',
        date: '2026-02-02',
      );
      expect(
        result,
        contains(
          '[Unreleased]: https://example.com/acme/widget/compare/v2.1.0...HEAD',
        ),
      );
      expect(
        result,
        contains(
          '[2.1.0]: https://example.com/acme/widget/compare/v2.0.0...v2.1.0',
        ),
      );
    });

    test('keeps the version heading awk-extractable and the [Unreleased] '
        'heading skipped', () {
      // publish.yml extracts the release notes with an awk pattern that keys on
      // `^## \\[?[0-9]...`: the dated version heading must match, and the fresh
      // empty [Unreleased] must NOT (else it would swallow the extraction).
      final result = finalizeChangelog(
        _changelog,
        version: '2.1.0',
        date: '2026-08-01',
      );
      final versionHeadings = result
          .split('\n')
          .where((l) => RegExp(r'^## \[?[0-9]+\.[0-9]+\.[0-9]+\]?').hasMatch(l))
          .toList();
      expect(versionHeadings, contains('## [2.1.0] - 2026-08-01'));
      expect(versionHeadings.any((l) => l.contains('Unreleased')), isFalse);
    });

    test('throws when there is no [Unreleased] heading', () {
      const noUnreleased = '''
## [2.0.0] - 2026-07-13

- something

[2.0.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.2.1...v2.0.0
''';
      expect(
        () => finalizeChangelog(
          noUnreleased,
          version: '2.1.0',
          date: '2026-08-01',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when there is no [Unreleased] compare link', () {
      const noLink = '''
## [Unreleased]

- pending

## [2.0.0] - 2026-07-13

- something
''';
      expect(
        () => finalizeChangelog(noLink, version: '2.1.0', date: '2026-08-01'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'throws when the version is already finalized (no double-finalize)',
      () {
        final once = finalizeChangelog(
          _changelog,
          version: '2.1.0',
          date: '2026-08-01',
        );
        expect(
          () => finalizeChangelog(once, version: '2.1.0', date: '2026-08-01'),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('throws on a non X.Y.Z version', () {
      expect(
        () =>
            finalizeChangelog(_changelog, version: 'v2.1', date: '2026-08-01'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on a malformed date (not YYYY-MM-DD)', () {
      // A typo or a flag accidentally consumed as the value must not be stamped
      // into the immutable released heading.
      for (final bad in ['13/07/2026', '--yes', '2026-7-1', 'today']) {
        expect(
          () => finalizeChangelog(_changelog, version: '2.1.0', date: bad),
          throwsA(isA<Exception>()),
          reason: 'date "$bad" should be rejected',
        );
      }
    });
  });

  group('insertChangelogEntry', () {
    const highlight = '**liboqs 0.17.0** — maintenance update';
    const changed = '- Update bundled liboqs native library to 0.17.0';

    test('creates an [Unreleased] section when none exists (this project\'s '
        'between-releases convention)', () {
      const noUnreleased = '''
## [2.0.0] - 2026-07-13

### For Users

- Bundled liboqs upgraded 0.15.0 → 0.16.0

[Unreleased]: https://github.com/djx-y-z/liboqs_dart/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.2.1...v2.0.0
''';
      final result = insertChangelogEntry(
        currentChangelog: noUnreleased,
        nativeHighlight: highlight,
        changed: changed,
      );

      final lines = result.split('\n');
      final unreleasedIdx = lines.indexWhere(
        (l) => l.startsWith('## [Unreleased]'),
      );
      final versionIdx = lines.indexWhere((l) => l.startsWith('## [2.0.0]'));
      expect(unreleasedIdx, isNot(-1));
      expect(unreleasedIdx, lessThan(versionIdx));
      // The new section carries the house structure with both entries.
      final section = lines.sublist(unreleasedIdx, versionIdx).join('\n');
      expect(section, contains('### For Users'));
      expect(section, contains('#### ✨ Highlights'));
      expect(section, contains('- $highlight'));
      expect(section, contains('#### Changed'));
      expect(section, contains(changed));
    });

    test('inserts into an existing [Unreleased] section without creating a '
        'second one', () {
      final result = insertChangelogEntry(
        currentChangelog: _changelog,
        nativeHighlight: highlight,
        changed: changed,
      );
      expect('## [Unreleased]'.allMatches(result).length, equals(1));
      expect(result, contains('- $highlight'));
      expect(result, contains(changed));
    });
  });
}
