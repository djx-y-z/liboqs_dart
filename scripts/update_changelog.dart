#!/usr/bin/env dart

/// Update CHANGELOG.md with AI-generated entry for a liboqs update.
///
/// This script uses GitHub Models API to analyze liboqs release notes
/// and generate an appropriate changelog entry.
///
/// Usage:
///   make update-changelog ARGS="--version 0.17.0 --from 0.16.0"
///
/// Options:
///   - `--version [ver]`   liboqs version (e.g., 0.17.0)
///   - `--from [ver]`      Previous version — enables upstream commit analysis
///   - `--ci`              CI mode: use AI_MODELS_TOKEN for API
///   - `--help, -h`        Show this help
///
/// Environment:
///   AI_MODELS_TOKEN   Required for GitHub Models API authentication
library;

import 'dart:io';

import 'src/update_changelog.dart';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  // Parse arguments
  final ciMode = args.contains('--ci');

  String? version;
  final versionIndex = args.indexOf('--version');
  if (versionIndex != -1 && versionIndex + 1 < args.length) {
    version = args[versionIndex + 1];
  }

  String? fromVersion;
  final fromIndex = args.indexOf('--from');
  if (fromIndex != -1 && fromIndex + 1 < args.length) {
    fromVersion = args[fromIndex + 1];
  }

  if (version == null) {
    print('Error: --version is required');
    print('');
    _printUsage();
    exit(1);
  }

  // Check for AI Models token
  final token = Platform.environment['AI_MODELS_TOKEN'];
  if (token == null || token.isEmpty) {
    print('Error: AI_MODELS_TOKEN environment variable is required');
    print('');
    print('Get a token from: https://github.com/settings/tokens');
    print('Required permission: Models → Read only');
    exit(1);
  }

  print('');
  print('========================================');
  print('  CHANGELOG Update with AI');
  print('========================================');
  print('');

  try {
    await updateChangelog(
      version: version,
      fromVersion: fromVersion,
      token: token,
      ciMode: ciMode,
    );
    print('');
    print('CHANGELOG.md updated successfully!');
  } catch (e) {
    print('Error: $e');
    exit(2);
  }
}

void _printUsage() {
  print('''
Update CHANGELOG.md with AI

Usage:
  make update-changelog ARGS="--version <ver> [options]"

Options:
  --version <ver>   liboqs version (e.g., 0.17.0) [required]
  --from <ver>      Previous liboqs version — when given, the
                    upstream commit list between the two tags is fed to the AI
                    for a more complete changelog entry, and a compare link is
                    used instead of a release-notes link
  --ci              CI mode
  --help, -h        Show this help

Environment:
  AI_MODELS_TOKEN   Required for GitHub Models API authentication
                    (github.com/settings/tokens, permission: Models -> Read)

Examples:
  # Update changelog for a specific version with commit analysis
  make update-changelog ARGS="--version 0.17.0 --from 0.16.0"

  # CI mode (token from environment)
  make update-changelog ARGS="--version 0.17.0 --from 0.16.0 --ci"
''');
}
