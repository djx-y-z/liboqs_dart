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
import 'third_party_notices.dart';

/// Cut a Dart package release for [version] (plain `X.Y.Z`).
///
/// Verifies the native release exists, runs `make publish-dry-run` (on the
/// clean, pre-bump tree), bumps `pubspec.yaml`, finalizes the CHANGELOG,
/// creates a signed commit + signed tag `vX.Y.Z`, and (unless [push] is false)
/// pushes `main` and the tag.
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
  const releaseFiles = ['pubspec.yaml', 'CHANGELOG.md'];

  // ---- Preconditions -------------------------------------------------------
  await ensureGitRepo();

  final branch = await git(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branch != 'main') {
    throw Exception(
      'Not on main (on "$branch"). Package releases are cut from main; '
      'check it out and pull first.',
    );
  }

  final status = await gitStatus();
  final treeClean = status.isEmpty;
  if (!treeClean) {
    // Interrupting a run (Ctrl-C) between the bump and the commit leaves
    // exactly this release's own files modified — and kills the script before
    // it can say what to do about it, so say it here instead.
    final hint = onlyTheseFilesDirty(status, releaseFiles)
        ? "Only this release's own files are modified, so an earlier run was "
              'probably interrupted before its commit. Discard it with: '
              "git restore --staged --worktree ${releaseFiles.join(' ')}"
        : 'Commit or stash changes first.';
    throw Exception('Working tree is not clean. $hint');
  }

  // ---- Resume an interrupted previous run ----------------------------------
  // A run that died between its commit and its tag — a Ctrl-C, a closed
  // terminal — already bumped, committed, and left nothing to tag with.
  // Recognise that exact state and continue from where it stopped, instead of
  // tripping the "must be greater" check below and leaving a manual
  // tag-and-push (or a commit to revert) as the only ways forward.
  final current = getPackageVersion();
  final commitSubject = 'chore: prepare release v$version';
  final resuming = isResumableRelease(
    requestedVersion: version,
    currentVersion: current,
    headSubject: await git(['log', '-1', '--pretty=%s']),
    expectedSubject: commitSubject,
    treeClean: treeClean,
  );

  if (resuming) {
    logWarn(
      'Resuming an interrupted release: "$commitSubject" is already the HEAD '
      'commit, so the version bump and the CHANGELOG edit are skipped.',
    );
  } else if (!isNewerVersion(version, current)) {
    throw Exception(
      'New version $version must be greater than the current '
      'pubspec version $current.',
    );
  }

  // A leftover tag is resumable only when it is this release's tag AND points
  // at the release commit; the same name on any other commit is a conflict this
  // must not push over.
  var tagCreated = false;
  if ((await git(['tag', '--list', tag])).isNotEmpty) {
    final tagged = await git(['rev-list', '-n', '1', tag]);
    if (resuming && tagged == await git(['rev-parse', 'HEAD'])) {
      tagCreated = true;
      logWarn('Tag $tag already exists on HEAD; skipping tag creation.');
    } else {
      throw Exception(
        'Tag $tag already exists locally, on ${tagged.substring(0, 7)}. '
        'Delete it (git tag -d $tag) or release a different version.',
      );
    }
  }

  // THIRD_PARTY_NOTICES.txt ships inside the published package, and a pub.dev
  // version cannot be replaced once published. Checked here rather than trusting
  // the last CI run, which may predate a local change to the generator. Placed
  // after the checks above because it clones liboqs: a mistyped version should
  // fail instantly rather than after a download.
  logStep('Verifying third-party notices match the pinned liboqs sources...');
  await assertNoticesCurrent();

  logStep('Fetching origin...');
  // Fetch only origin/main — all the behind/ahead check below needs. Not tags:
  // the "tag already on origin?" check right below asks `git ls-remote` directly,
  // so `--tags` adds nothing, while a single diverged tag anywhere in the
  // namespace (a rebuilt liboqs-* native tag, say) would fail the fetch and abort
  // an otherwise valid release.
  await git(['fetch', 'origin', 'main', '--no-tags', '--quiet']);
  if ((await git(['ls-remote', '--tags', 'origin', tag])).isNotEmpty) {
    throw Exception(
      'Tag $tag already exists on origin — v$version is already released. '
      'Release a higher version.',
    );
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
    final check = await checkNativeRelease(fullVersion);
    switch (check.status) {
      case NativeReleaseStatus.exists:
        logInfo('Found native release liboqs-$fullVersion.');
      case NativeReleaseStatus.missing:
        throw Exception(
          'Native release liboqs-$fullVersion does not exist yet. '
          'Run `make release-native` on main (it pushes the liboqs-$fullVersion '
          'tag, which triggers build-liboqs.yml) and let the build finish, or '
          'pass --skip-release-check if you have verified the release exists '
          'manually.',
        );
      case NativeReleaseStatus.inconclusive:
        throw Exception(
          'Could not verify the native release liboqs-$fullVersion '
          '(${check.detail}). Verify it exists on GitHub Releases, then '
          're-run with --skip-release-check.',
        );
    }
  }

  // ---- Validate (pub.dev dry-run) ------------------------------------------
  // Deliberately before the bump, on the clean tree. `dart pub publish
  // --dry-run` exits 65 on ANY warning, and dry-running the
  // bumped-but-uncommitted tree raises a "checked-in files are modified in git"
  // warning of its own — a self-inflicted failure that made every release abort
  // here. The dry-run only validates package structure (files present, archive
  // size, pubspec validity), which a version bump or a CHANGELOG edit cannot
  // change, so checking before the bump catches exactly as much. Nothing has
  // been modified yet either, so there is nothing to revert on failure.
  logStep('Validating the package (make publish-dry-run)...');
  await runInherit('make', [
    'publish-dry-run',
  ], failMessage: 'publish-dry-run reported errors');

  // ---- Prepare files -------------------------------------------------------
  if (resuming) {
    logStep('Commit to be tagged:');
    await runInherit('git', ['--no-pager', 'log', '-1', '--oneline', '--stat']);
  } else {
    logStep('Bumping pubspec.yaml version: $current -> $version');
    _bumpPubspecVersion(packageDir, version);

    logStep(
      'Finalizing CHANGELOG: [Unreleased] -> [$version] - $releaseDate...',
    );
    _finalizeChangelogFile(packageDir, version, releaseDate);

    logStep('Changes to be committed:');
    await runInherit('git', ['--no-pager', 'diff', '--stat', ...releaseFiles]);
  }

  // ---- Confirm -------------------------------------------------------------
  if (resuming && tagCreated && !push) {
    logSuccess('Nothing left to do: the commit and tag $tag already exist.');
    logInfo('When ready: git push origin main && git push origin $tag');
    return;
  }

  final steps = [
    if (!resuming) 'commit',
    if (!tagCreated) 'tag $tag',
    if (push) 'PUSH',
  ].join(' + ');
  final action = push
      ? '$steps (this triggers the pub.dev publish)'
      : '$steps (no push)';
  if (!assumeYes && !confirm('Proceed to $action?')) {
    if (resuming) {
      logWarn(
        'Aborted. The release commit${tagCreated ? " and tag $tag are" : " is"} '
        'left in place — re-run the same command to continue from here.',
      );
    } else {
      await git(['checkout', '--', ...releaseFiles]);
      logWarn('Aborted. Reverted pubspec.yaml and CHANGELOG.md.');
    }
    return;
  }

  // ---- Commit + tag (signed via ssh-agent) ---------------------------------
  // Every step past this point goes through `runInheritRetry`: a mistyped
  // passphrase is not re-prompted by the signing tool, and aborting here would
  // strand the release mid-sequence.
  if (!resuming) {
    logStep('Committing (signed; requires your key in ssh-agent)...');
    await runInherit('git', ['add', ...releaseFiles]);
    await runInheritRetry(
      'git',
      ['commit', '-m', commitSubject],
      what: 'git commit',
      alreadyDone: () async =>
          await git(['log', '-1', '--pretty=%s']) == commitSubject,
      // A pre-commit hook may rewrite a staged file; re-stage so the retry
      // commits what the hook produced rather than failing the same way again.
      beforeRetry: () => runInherit('git', ['add', ...releaseFiles]),
      failMessage:
          'git commit failed (pre-commit checks or signing). The version bump '
          'is still staged — fix the issue and re-run `git commit`/`git tag` '
          'manually, or discard it with `git restore --staged --worktree '
          'pubspec.yaml CHANGELOG.md` and re-run the release.',
    );
  }

  if (!tagCreated) {
    logStep('Creating signed tag $tag...');
    await runInheritRetry(
      'git',
      ['tag', '-s', tag, '-m', 'Release v$version'],
      what: 'git tag',
      alreadyDone: () async => (await git(['tag', '--list', tag])).isNotEmpty,
      failMessage:
          'git tag failed. The release commit exists but is not tagged. '
          'Re-run the same command to resume from here, or tag manually: '
          'git tag -s $tag -m "Release v$version"',
    );
  }

  // ---- Push ----------------------------------------------------------------
  if (!push) {
    logSuccess('Committed and tagged $tag locally (not pushed).');
    logInfo('When ready: git push origin main && git push origin $tag');
    return;
  }

  logStep('Pushing main and tag $tag...');
  await runInheritRetry(
    'git',
    ['push', 'origin', 'main'],
    what: 'git push origin main',
    failMessage:
        'git push origin main failed. The commit and tag $tag exist locally; '
        're-run the same command to resume from here.',
  );
  await runInheritRetry(
    'git',
    ['push', 'origin', tag],
    what: 'git push origin $tag',
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
///  1. Renames the `## [Unreleased]` heading to `## [version] - date` in place
///     (in-progress content becomes the released section). No empty
///     `## [Unreleased]` is left behind — whoever records the next unreleased
///     change recreates it, by hand or via `insertChangelogEntry` in
///     update_changelog.dart, which creates the section when it is absent.
///  2. Rewrites the bottom `[Unreleased]:` compare link to span
///     `v<version>...HEAD`.
///  3. Inserts a `[version]:` compare link spanning `v<previous>...v<version>`.
///
/// The previous version and the repo base URL are read from the existing
/// `[Unreleased]:` link — the single source of truth for the compare range — so
/// the function needs no repo slug. That footer link is deliberately kept even
/// while no `## [Unreleased]` heading references it: this function and the
/// section-creating scripts both read it, so it must NOT be deleted as stale.
/// Throws if the CHANGELOG lacks a `## [Unreleased]` heading or an
/// `[Unreleased]:` compare link, or already has a `## [version]` section.
String finalizeChangelog(
  String content, {
  required String version,
  required String date,
}) {
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    throw Exception('Version must be plain X.Y.Z (got "$version").');
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
    throw Exception('Date must be YYYY-MM-DD (got "$date").');
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

  // Then rename the `## [Unreleased]` heading to the finalized
  // `## [version] - date` heading, in place. No fresh empty [Unreleased] is
  // emitted: an empty section shipped to pub.dev with every release, and the
  // scripts that record unreleased changes create it when it is missing.
  lines[unreleasedIdx] = '## [$version] - $date';

  return lines.join('\n');
}

/// Today's date as `YYYY-MM-DD` (local time).
String _today() {
  final now = DateTime.now();
  String pad(int v, [int width = 2]) => v.toString().padLeft(width, '0');
  return '${pad(now.year, 4)}-${pad(now.month)}-${pad(now.day)}';
}
