// Release a new Dart package version (publish to pub.dev).
//
// Single-stage release flow: the native liboqs libraries are built and
// published to a GitHub Release (`liboqs-<native_version>-<native_build>`) by
// `build-liboqs.yml` ahead of time, so releasing the Dart package is:
//   verify the native release exists → bump pubspec.yaml → finalize the
//   CHANGELOG `[Unreleased]` → `[X.Y.Z]` → validate with a publish dry-run →
//   commit + tag `vX.Y.Z` → push. The tag triggers publish.yml, which
//   publishes to pub.dev via OIDC (its build hook downloads the native
//   release, which must already exist).
//
// The commit and the tag are signed via your git config (SSH signing key —
// make sure it is loaded into ssh-agent first: `ssh-add -l`). The git
// subprocesses inherit this terminal (stdio), so any interactive prompt works
// mid-run.
library;

import 'dart:io';

import 'common.dart';
import 'release_common.dart';

/// Cut a Dart package release for [version] (plain `X.Y.Z`).
///
/// Verifies the native release exists, bumps `pubspec.yaml`, finalizes the
/// CHANGELOG, runs `make publish-dry-run`, creates a signed commit + signed
/// tag `vX.Y.Z`, and (unless [push] is false) pushes `main` and the tag.
/// Prompts for confirmation before committing unless [assumeYes]. Set
/// [skipReleaseCheck] only if you have manually verified the native release
/// exists. [date] defaults to today (YYYY-MM-DD) and is used for the
/// CHANGELOG heading.
Future<void> releasePackage({
  required String version,
  bool push = true,
  bool assumeYes = false,
  bool skipReleaseCheck = false,
  String? date,
}) async {
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    throw Exception('Version must be plain X.Y.Z (got "$version").');
  }

  final releaseDate = date ?? _today();
  final packageDir = getPackageDir();
  final tag = 'v$version';

  // ---- Preconditions -------------------------------------------------------
  await ensureGitRepo();

  final branch = await git(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branch != 'main') {
    throw Exception(
      'Not on main (on "$branch"). Package releases are cut from main; '
      'check it out and pull first.',
    );
  }

  if ((await git(['status', '--porcelain'])).isNotEmpty) {
    throw Exception(
      'Working tree is not clean. Commit or stash changes first.',
    );
  }

  final current = getPackageVersion();
  if (!isNewerVersion(version, current)) {
    throw Exception(
      'New version $version must be greater than the current '
      'pubspec version $current.',
    );
  }

  if ((await git(['tag', '--list', tag])).isNotEmpty) {
    throw Exception('Tag $tag already exists locally.');
  }

  logStep('Fetching origin...');
  await git(['fetch', 'origin', '--tags', '--quiet']);
  if ((await git(['ls-remote', '--tags', 'origin', tag])).isNotEmpty) {
    throw Exception('Tag $tag already exists on origin.');
  }

  final behind = await git(['rev-list', '--count', 'HEAD..origin/main']);
  if (behind != '0') {
    throw Exception(
      'Local main is behind origin/main by $behind commit(s). '
      'Run: git pull --ff-only origin main',
    );
  }
  final ahead = await git(['rev-list', '--count', 'origin/main..HEAD']);
  if (ahead != '0') {
    logWarn(
      'Local main is ahead of origin/main by $ahead commit(s); these '
      'will be pushed together with the release commit.',
    );
  }

  // ---- Prerequisite: the native release must already exist -----------------
  // The published package's build hook downloads the `liboqs-<fullVersion>`
  // release; if it doesn't exist yet, consuming builds fail. Fail closed
  // (block) unless the release is explicitly told the check was done manually.
  final fullVersion = getFullVersion();
  if (skipReleaseCheck) {
    logWarn(
      '--skip-release-check: NOT verifying that the liboqs-$fullVersion '
      'native release exists. Make sure the native build finished.',
    );
  } else {
    logStep('Verifying the native release liboqs-$fullVersion exists...');
    final check = await _checkNativeRelease(fullVersion);
    switch (check.status) {
      case _NativeReleaseStatus.exists:
        logInfo('Found native release liboqs-$fullVersion.');
      case _NativeReleaseStatus.missing:
        throw Exception(
          'Native release liboqs-$fullVersion does not exist yet. '
          'Merge the version bump into main and let build-liboqs.yml finish '
          '(it publishes the native libraries), or pass --skip-release-check '
          'if you have verified the release exists manually.',
        );
      case _NativeReleaseStatus.inconclusive:
        throw Exception(
          'Could not verify the native release liboqs-$fullVersion '
          '(${check.detail}). Verify it exists on GitHub Releases, then '
          're-run with --skip-release-check.',
        );
    }
  }

  // ---- Prepare files -------------------------------------------------------
  logStep('Bumping pubspec.yaml version: $current -> $version');
  _bumpPubspecVersion(packageDir, version);

  logStep('Finalizing CHANGELOG: [Unreleased] -> [$version] - $releaseDate...');
  _finalizeChangelogFile(packageDir, version, releaseDate);

  logStep('Changes to be committed:');
  await runInherit('git', [
    '--no-pager',
    'diff',
    '--stat',
    'pubspec.yaml',
    'CHANGELOG.md',
  ]);

  // ---- Validate (pub.dev dry-run) ------------------------------------------
  // Runs on the bumped-but-uncommitted tree. pub exits 0 on warnings; only a
  // real error (invalid pubspec, missing files, oversized package) exits
  // non-zero and aborts here.
  logStep('Validating the package (make publish-dry-run)...');
  try {
    await runInherit('make', [
      'publish-dry-run',
    ], failMessage: 'publish-dry-run reported errors');
  } catch (e) {
    await git(['checkout', '--', 'pubspec.yaml', 'CHANGELOG.md']);
    logWarn('Reverted pubspec.yaml and CHANGELOG.md.');
    rethrow;
  }

  // ---- Confirm -------------------------------------------------------------
  final action = push
      ? 'commit + tag $tag + PUSH (this triggers the pub.dev publish)'
      : 'commit + tag $tag (no push)';
  if (!assumeYes && !confirm('Proceed to $action?')) {
    await git(['checkout', '--', 'pubspec.yaml', 'CHANGELOG.md']);
    logWarn('Aborted. Reverted pubspec.yaml and CHANGELOG.md.');
    return;
  }

  // ---- Commit + tag (signed via ssh-agent) ---------------------------------
  logStep('Committing (signed; requires your key in ssh-agent)...');
  await runInherit('git', ['add', 'pubspec.yaml', 'CHANGELOG.md']);
  await runInherit('git', [
    'commit',
    '-m',
    'chore: prepare release v$version',
  ], failMessage: 'git commit failed (pre-commit checks or signing).');

  logStep('Creating signed tag $tag...');
  await runInherit(
    'git',
    ['tag', '-s', tag, '-m', 'Release v$version'],
    failMessage:
        'git tag failed. The release commit was created; tag manually '
        'with: git tag -s $tag -m "Release v$version"',
  );

  // ---- Push ----------------------------------------------------------------
  if (!push) {
    logSuccess('Committed and tagged $tag locally (not pushed).');
    logInfo('When ready: git push origin main && git push origin $tag');
    return;
  }

  logStep('Pushing main and tag $tag...');
  await runInherit('git', [
    'push',
    'origin',
    'main',
  ], failMessage: 'git push origin main failed.');
  await runInherit(
    'git',
    ['push', 'origin', tag],
    failMessage: 'git push tag failed. Push it manually: git push origin $tag',
  );

  logSuccess('Pushed. "Publish to pub.dev" will publish v$version.');
  logInfo('Watch it: gh run watch (or the Actions tab).');
}

/// Rewrites the top-level `version:` in pubspec.yaml to [version].
void _bumpPubspecVersion(Directory packageDir, String version) {
  final file = File('${packageDir.path}/pubspec.yaml');
  final content = file.readAsStringSync();
  final pattern = RegExp(r'^(version:\s*).+$', multiLine: true);
  if (!pattern.hasMatch(content)) {
    throw Exception('Could not find a top-level `version:` in pubspec.yaml.');
  }
  file.writeAsStringSync(
    content.replaceFirstMapped(pattern, (m) => '${m.group(1)}$version'),
  );
}

/// Finalizes CHANGELOG.md on disk for [version] released on [date].
void _finalizeChangelogFile(Directory packageDir, String version, String date) {
  final file = File('${packageDir.path}/CHANGELOG.md');
  file.writeAsStringSync(
    finalizeChangelog(file.readAsStringSync(), version: version, date: date),
  );
}

/// Returns [content] with the CHANGELOG finalized for releasing [version] on
/// [date] (YYYY-MM-DD). Pure; exposed for testing.
///
/// Three edits:
///  1. Renames the `## [Unreleased]` heading to `## [version] - date`, leaving
///     a fresh empty `## [Unreleased]` above it (in-progress content becomes the
///     released section).
///  2. Rewrites the bottom `[Unreleased]:` compare link to span
///     `v<version>...HEAD`.
///  3. Inserts a `[version]:` compare link spanning `v<previous>...v<version>`.
///
/// The previous version and the repo base URL are read from the existing
/// `[Unreleased]:` link — the single source of truth for the compare range — so
/// the function needs no repo slug. Throws if the CHANGELOG lacks a
/// `## [Unreleased]` heading or an `[Unreleased]:` compare link, or already has a
/// `## [version]` section.
String finalizeChangelog(
  String content, {
  required String version,
  required String date,
}) {
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    throw Exception('Version must be plain X.Y.Z (got "$version").');
  }

  final lines = content.split('\n');

  // Guard: already finalized for this version?
  if (lines.any((l) => l.startsWith('## [$version]'))) {
    throw Exception('CHANGELOG already has a "## [$version]" section.');
  }

  // 1. Locate the `## [Unreleased]` heading.
  final unreleasedIdx = lines.indexWhere(
    (l) => l.startsWith('## [Unreleased]'),
  );
  if (unreleasedIdx == -1) {
    throw Exception('No "## [Unreleased]" heading found in CHANGELOG.');
  }

  // 2. Locate + parse the `[Unreleased]:` compare link (base URL + previous
  //    version). Its left side is, by construction, the last released version.
  final linkPattern = RegExp(
    r'^\[Unreleased\]:\s*(\S+?)/compare/v(\d+\.\d+\.\d+)\.\.\.HEAD\s*$',
  );
  var linkIdx = -1;
  String? base;
  String? previous;
  for (var i = 0; i < lines.length; i++) {
    final m = linkPattern.firstMatch(lines[i]);
    if (m != null) {
      linkIdx = i;
      base = m.group(1);
      previous = m.group(2);
      break;
    }
  }
  if (linkIdx == -1) {
    throw Exception(
      'No "[Unreleased]: <base>/compare/vX.Y.Z...HEAD" link found at the '
      'bottom of the CHANGELOG.',
    );
  }

  // Rewrite the compare links first (they sit below the heading, so editing
  // them by value is unaffected by the heading edit that follows).
  lines[linkIdx] = '[Unreleased]: $base/compare/v$version...HEAD';
  lines.insert(linkIdx + 1, '[$version]: $base/compare/v$previous...v$version');

  // Then split the single `## [Unreleased]` heading into a fresh empty
  // [Unreleased] followed by the finalized `## [version] - date` heading.
  lines.replaceRange(unreleasedIdx, unreleasedIdx + 1, [
    '## [Unreleased]',
    '',
    '## [$version] - $date',
  ]);

  return lines.join('\n');
}

/// Whether the native release for the current full version exists.
enum _NativeReleaseStatus { exists, missing, inconclusive }

/// Outcome of a native-release existence check.
class _NativeCheck {
  _NativeCheck(this.status, [this.detail = '']);
  final _NativeReleaseStatus status;
  final String detail;
}

/// Checks whether the GitHub Release `liboqs-<fullVersion>` exists, using the
/// `gh` CLI (which auto-resolves the repo from the git remote).
///
/// Distinguishes a definite "missing" (gh reports "release not found") from an
/// "inconclusive" result (gh absent, not authenticated, or a network/API
/// error) so the caller can fail closed on both while giving a useful message.
Future<_NativeCheck> _checkNativeRelease(String fullVersion) async {
  final tag = 'liboqs-$fullVersion';

  if (!await commandExists('gh')) {
    return _NativeCheck(
      _NativeReleaseStatus.inconclusive,
      'the `gh` CLI is not installed',
    );
  }

  final result = await Process.run('gh', [
    'release',
    'view',
    tag,
    '--json',
    'tagName',
  ]);
  if (result.exitCode == 0) {
    return _NativeCheck(_NativeReleaseStatus.exists);
  }

  final stderr = (result.stderr as String).trim();
  if (stderr.toLowerCase().contains('release not found')) {
    return _NativeCheck(_NativeReleaseStatus.missing);
  }
  return _NativeCheck(
    _NativeReleaseStatus.inconclusive,
    stderr.isEmpty ? 'gh release view exited ${result.exitCode}' : stderr,
  );
}

/// Today's date as `YYYY-MM-DD` (local time).
String _today() {
  final now = DateTime.now();
  String pad(int v, [int width = 2]) => v.toString().padLeft(width, '0');
  return '${pad(now.year, 4)}-${pad(now.month)}-${pad(now.day)}';
}
