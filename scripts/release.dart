#!/usr/bin/env dart

/// Release a new Dart package version (publish to pub.dev).
///
/// Verifies the native release exists, bumps `pubspec.yaml`, finalizes the
/// CHANGELOG `[Unreleased]` → `[X.Y.Z]`, validates with `make
/// publish-dry-run`, creates a signed commit + signed tag `vX.Y.Z`, and pushes
/// (unless `--no-push`). The tag triggers `publish.yml`, which publishes to
/// pub.dev via OIDC.
///
/// The commit and tag are signed with your SSH signing key — load it into
/// ssh-agent first (`ssh-add -l` to check). The git subprocesses inherit this
/// terminal, so interactive prompts work during the command.
///
/// Usage:
///   make release ARGS="--version X.Y.Z"
///   make release ARGS="--version X.Y.Z --no-push"
///   make release ARGS="--version X.Y.Z --yes"
///   make release ARGS="--version X.Y.Z --skip-release-check"
library;

import 'dart:io';

import 'src/release.dart';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  String? optionValue(String name) {
    final i = args.indexOf(name);
    if (i != -1 && i + 1 < args.length) return args[i + 1];
    return null;
  }

  final version = optionValue('--version');
  final date = optionValue('--date');
  final push = !args.contains('--no-push');
  final assumeYes = args.contains('--yes') || args.contains('-y');
  final skipReleaseCheck = args.contains('--skip-release-check');

  if (version == null) {
    print('Error: --version X.Y.Z is required');
    print('');
    _printUsage();
    exit(1);
  }

  print('');
  print('========================================');
  print('  Release Dart package (pub.dev)');
  print('========================================');
  print('');

  try {
    await releasePackage(
      version: version,
      push: push,
      assumeYes: assumeYes,
      skipReleaseCheck: skipReleaseCheck,
      date: date,
    );
  } catch (e) {
    print('');
    print('Error: $e');
    exit(2);
  }
}

void _printUsage() {
  print('''
Release a new Dart package version (publish to pub.dev)

Usage:
  make release ARGS="--version X.Y.Z [options]"

Options:
  --version <X.Y.Z>     New package version [required]
  --no-push             Commit and tag locally, but do not push
  --yes, -y             Skip the confirmation prompt
  --skip-release-check  Skip the native-release existence check
                        (only if you have verified it manually)
  --date <Y-M-D>        CHANGELOG date to stamp (default: today)
  --help, -h            Show this help

What it does:
  1. Verifies you are on a clean, up-to-date main.
  2. Verifies the native release liboqs-<native_version>-<native_build> exists
     on GitHub Releases (the published build hook downloads it).
  3. Bumps the version in pubspec.yaml.
  4. Finalizes CHANGELOG: [Unreleased] -> [X.Y.Z] - <date>, adds a fresh empty
     [Unreleased], and updates the compare links at the bottom.
  5. Validates the package with `make publish-dry-run`.
  6. Creates a SIGNED commit and SIGNED tag "vX.Y.Z" (your SSH signing key
     must be loaded in ssh-agent).
  7. Pushes main and the tag, which triggers the pub.dev publish workflow.

The native libraries must already be published: after the version bump merges
into main, `make release-native` pushes the liboqs-<fullVersion> tag, which
triggers build-liboqs.yml to build them and create the release. Run
`make release` only after that build finished.
''');
}
