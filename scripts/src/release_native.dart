// Release the native liboqs libraries: tag-and-push the build trigger.
//
// `build-liboqs.yml` triggers on a `liboqs-<fullVersion>` tag push
// (libsignal-style; see the workflow header). This script cuts that tag
// deliberately from main. Unlike libsignal's stage-1 `release-frb` it commits
// nothing — the version bump (`liboqs.native_version` / `native_build` in
// pubspec.yaml) has already landed on main via the merged update PR — so all
// that remains is: verify preconditions, create a signed tag on the exact
// origin/main commit, and push it.
//
// The tag is signed via your git config (SSH signing key — make sure it is
// loaded into ssh-agent first: `ssh-add -l`). The git subprocesses inherit
// this terminal (stdio), so any interactive prompt works mid-run.
library;

import 'common.dart';
import 'release_common.dart';

/// Creates and pushes the signed tag `liboqs-<fullVersion>` for the version
/// currently in pubspec.yaml, which triggers the native build workflow.
///
/// Fails closed unless: on a clean `main`, neither behind nor ahead of
/// `origin/main` (only the tag is pushed, so it must point at a commit that is
/// already on origin/main), and the tag does not exist locally or on origin —
/// the tag check is the primary "already built" gate, since the release is
/// created on this same tag. A secondary `gh` release-existence check catches
/// the release-without-tag corner (skippable with [skipReleaseCheck]).
/// Prompts for confirmation before tagging unless [assumeYes]; [push] false
/// tags locally only.
Future<void> releaseNative({
  bool push = true,
  bool assumeYes = false,
  bool skipReleaseCheck = false,
}) async {
  // ---- Preconditions -------------------------------------------------------
  await ensureGitRepo();

  final branch = await git(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branch != 'main') {
    throw Exception(
      'Not on main (on "$branch"). Native releases are tagged on main '
      '(after the version-bump PR merged); check it out and pull first.',
    );
  }

  if ((await git(['status', '--porcelain'])).isNotEmpty) {
    throw Exception(
      'Working tree is not clean. Commit or stash changes first.',
    );
  }

  final version = getLiboqsVersion();
  final build = getNativeBuild();
  final fullVersion = getFullVersion();
  final tag = 'liboqs-$fullVersion';

  // The release is created ON this tag, so an existing tag means this
  // fullVersion was already released (or a release attempt is in flight).
  const rebuildHint =
      'To rebuild the same version: delete the release and its tag '
      '(gh release delete <tag> --cleanup-tag --yes), then re-run '
      '`make release-native`. To ship a new build of the same liboqs '
      'version, bump liboqs.native_build in pubspec.yaml instead.';

  if ((await git(['tag', '--list', tag])).isNotEmpty) {
    throw Exception(
      'Tag $tag already exists locally — this native version is already '
      'tagged (did the update PR land and did you pull?). $rebuildHint',
    );
  }

  logStep('Fetching origin...');
  // Fetch only origin/main — all the behind/ahead check below needs. Not tags:
  // the "tag already on origin?" check right below asks `git ls-remote` directly,
  // so `--tags` adds nothing, while a single diverged tag anywhere in the
  // namespace would fail the fetch and abort an otherwise valid native release.
  await git(['fetch', 'origin', 'main', '--no-tags', '--quiet']);
  if ((await git(['ls-remote', '--tags', 'origin', tag])).isNotEmpty) {
    throw Exception(
      'Tag $tag already exists on origin — this native version is already '
      'released (or its build is in flight). $rebuildHint',
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
    throw Exception(
      'Local main is ahead of origin/main by $ahead commit(s). Only the tag '
      'is pushed, so it must point at a commit that is already on '
      'origin/main. Push your commits first: git push origin main',
    );
  }

  // ---- Secondary gate: the release must NOT already exist ------------------
  // Normally implied by the tag checks above (the release lives on the tag),
  // but a release can exist without its tag after a partial manual cleanup.
  if (skipReleaseCheck) {
    logWarn(
      '--skip-release-check: NOT verifying that the $tag release is absent.',
    );
  } else {
    logStep('Verifying no $tag release exists yet...');
    final check = await checkNativeRelease(fullVersion);
    switch (check.status) {
      case NativeReleaseStatus.missing:
        logInfo('No $tag release yet — good to go.');
      case NativeReleaseStatus.exists:
        throw Exception(
          'The release $tag already exists on GitHub (without a matching '
          'tag). $rebuildHint',
        );
      case NativeReleaseStatus.inconclusive:
        throw Exception(
          'Could not verify the $tag release is absent (${check.detail}). '
          'Check GitHub Releases, then re-run with --skip-release-check.',
        );
    }
  }

  // ---- Confirm -------------------------------------------------------------
  final head = await git(['rev-parse', '--short', 'HEAD']);
  logInfo('Will tag origin/main commit $head as $tag.');
  final action = push
      ? 'create signed tag $tag + PUSH (this triggers the native build)'
      : 'create signed tag $tag (no push)';
  if (!assumeYes && !confirm('Proceed to $action?')) {
    logWarn('Aborted. Nothing was created.');
    return;
  }

  // ---- Tag + push (signed via ssh-agent) -----------------------------------
  logStep('Creating signed tag $tag (requires your key in ssh-agent)...');
  await runInherit(
    'git',
    ['tag', '-s', tag, '-m', 'liboqs $version (build $build) native libraries'],
    failMessage:
        'git tag failed (signing?). Nothing was pushed; fix and re-run.',
  );

  if (!push) {
    logSuccess('Created tag $tag locally (not pushed).');
    logInfo('When ready: git push origin $tag');
    return;
  }

  logStep('Pushing tag $tag...');
  await runInherit(
    'git',
    ['push', 'origin', tag],
    failMessage:
        'git push failed. The local tag exists; push it manually '
        '(git push origin $tag) or delete it (git tag -d $tag).',
  );

  logSuccess(
    'Pushed. "Build liboqs Native Libraries" will build and publish $tag.',
  );
  logInfo('Watch it: gh run watch (or the Actions tab).');
  logInfo(
    'After the native build succeeds, the package release can follow: '
    'make release ARGS="--version X.Y.Z".',
  );
}
