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
import 'third_party_notices.dart';

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

  // Every archive built from this tag embeds THIRD_PARTY_NOTICES.txt, and a
  // pushed release tag cannot be taken back. The build workflow checks this too,
  // but failing here costs seconds instead of a whole build matrix.
  logStep('Verifying third-party notices match the pinned liboqs sources...');
  await assertNoticesCurrent();

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

  // ---- Resume an interrupted previous run ----------------------------------
  // This script commits nothing, so its half-finished state is narrower than a
  // package release's: the tag was created and the push failed (a Ctrl-C, a
  // closed terminal). Re-running then hit the "already tagged" throw below,
  // leaving `git push origin <tag>` by hand as the only way forward.
  //
  // Deliberately placed after the checks above, all of which the safety of this
  // argument depends on: the tag is NOT on origin (else the throw above fired),
  // and `ahead == 0` pins HEAD to origin/main. A local-only tag on that commit
  // can therefore only have come from this script's own failed push, so pushing
  // it is exactly what the interrupted run was about to do. A tag of the same
  // name anywhere else is still a conflict and still throws.
  var tagCreated = false;
  if ((await git(['tag', '--list', tag])).isNotEmpty) {
    final tagged = await git(['rev-list', '-n', '1', tag]);
    if (tagged == await git(['rev-parse', 'HEAD'])) {
      tagCreated = true;
      logWarn(
        'Tag $tag already exists on HEAD and is not on origin — resuming an '
        'interrupted release at the push step.',
      );
    } else {
      throw Exception(
        'Tag $tag already exists locally, on ${tagged.substring(0, 7)}, which '
        'is not the commit to release — this native version is already tagged '
        '(did the update PR land and did you pull?). $rebuildHint',
      );
    }
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
  if (tagCreated && !push) {
    logSuccess('Nothing left to do: tag $tag already exists on HEAD.');
    logInfo('When ready: git push origin $tag');
    return;
  }

  final head = await git(['rev-parse', '--short', 'HEAD']);
  logInfo(
    tagCreated
        ? 'Tag $tag already points at origin/main commit $head; only the push '
              'is left.'
        : 'Will tag origin/main commit $head as $tag.',
  );
  final steps = [
    if (!tagCreated) 'create signed tag $tag',
    if (push) 'PUSH',
  ].join(' + ');
  final action = push
      ? '$steps (this triggers the native build)'
      : '$steps (no push)';
  if (!assumeYes && !confirm('Proceed to $action?')) {
    logWarn(
      tagCreated
          ? 'Aborted. The local tag $tag is left in place — re-run the same '
                'command to push it.'
          : 'Aborted. Nothing was created.',
    );
    return;
  }

  // ---- Tag + push (signed via ssh-agent) -----------------------------------
  // Both steps go through `runInheritRetry`: a mistyped passphrase is not
  // re-prompted by the signing tool, and aborting between them would leave the
  // tag created but unpushed.
  if (!tagCreated) {
    logStep('Creating signed tag $tag (requires your key in ssh-agent)...');
    await runInheritRetry(
      'git',
      [
        'tag',
        '-s',
        tag,
        '-m',
        'liboqs $version (build $build) native libraries',
      ],
      what: 'git tag',
      alreadyDone: () async => (await git(['tag', '--list', tag])).isNotEmpty,
      failMessage:
          'git tag failed (signing?). Nothing was pushed; fix and re-run.',
    );
  }

  if (!push) {
    logSuccess('Created tag $tag locally (not pushed).');
    logInfo('When ready: git push origin $tag');
    return;
  }

  logStep('Pushing tag $tag...');
  await runInheritRetry(
    'git',
    ['push', 'origin', tag],
    what: 'git push origin $tag',
    failMessage:
        'git push failed. The local tag exists; re-run the same command to '
        'push it, push it manually (git push origin $tag), or delete it '
        '(git tag -d $tag).',
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
