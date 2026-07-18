#!/usr/bin/env dart

/// Release the native liboqs libraries for the version already in pubspec.yaml.
///
/// Creates a signed tag `liboqs-<native_version>-<native_build>` on the exact
/// `origin/main` commit and pushes it (unless `--no-push`). The tag triggers
/// `build-liboqs.yml`, which builds the native libraries for all platforms and
/// publishes them as a GitHub Release on that same tag.
///
/// Run this AFTER the liboqs version-bump PR has merged to main (merging no
/// longer starts a build by itself). Nothing is committed — the script only
/// tags and pushes.
///
/// The tag is signed with your SSH signing key — load it into ssh-agent first
/// (`ssh-add -l` to check). The git subprocesses inherit this terminal, so
/// interactive prompts work during the command.
///
/// Usage:
///   make release-native
///   make release-native ARGS="--no-push"
///   make release-native ARGS="--yes"
library;

import 'dart:io';

import 'src/release_native.dart';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  final push = !args.contains('--no-push');
  final assumeYes = args.contains('--yes') || args.contains('-y');
  final skipReleaseCheck = args.contains('--skip-release-check');

  print('');
  print('========================================');
  print('  Release native liboqs libraries');
  print('========================================');
  print('');

  try {
    await releaseNative(
      push: push,
      assumeYes: assumeYes,
      skipReleaseCheck: skipReleaseCheck,
    );
  } catch (e) {
    print('');
    print('Error: $e');
    exit(2);
  }
}

void _printUsage() {
  print('''
Release the native liboqs libraries (tag-triggered CI build)

Usage:
  make release-native [ARGS="..."]

Options:
  --no-push             Create the signed tag locally, but do not push
  --yes, -y             Skip the confirmation prompt
  --skip-release-check  Skip the secondary "release already exists" gh check
                        (the tag existence check still applies)
  --help, -h            Show this help

What it does:
  1. Verifies you are on a clean main, in sync with origin/main (neither
     behind nor ahead — only the tag is pushed, so it must point at a commit
     already on origin/main).
  2. Reads liboqs.native_version/native_build from pubspec.yaml and verifies
     the tag liboqs-<fullVersion> does not exist locally or on origin, and
     that no such GitHub Release exists.
  3. Creates a SIGNED tag "liboqs-<fullVersion>" (your SSH signing key must
     be loaded in ssh-agent) and pushes it.
  4. The tag triggers build-liboqs.yml, which builds all platforms and
     publishes the GitHub Release consumed by the build hook.

There is no version bump and no commit here: run this after the liboqs
update PR (which bumps pubspec.yaml) has merged to main. To rebuild an
already-released version: gh release delete liboqs-X.Y.Z-N --cleanup-tag
--yes, then re-run. For a new build of the same liboqs version, bump
liboqs.native_build in pubspec.yaml via a PR first.

After the native build succeeds, release the package: make release
ARGS="--version X.Y.Z".
''');
}
