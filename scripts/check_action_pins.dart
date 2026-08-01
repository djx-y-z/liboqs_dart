#!/usr/bin/env dart

/// Verify that every third-party action referenced by a workflow really exists.
///
/// `publish.yml` and `build-liboqs.yml` only ever run during a release, so a
/// mistyped `uses:` in either of them is discovered at the worst possible
/// moment. actionlint does not help here: it is an offline linter with a
/// bundled snapshot of popular actions, and on a ref it does not recognise it
/// silently disables its checks rather than reporting one — a fabricated
/// `owner/repo@v999` and a fabricated 40-character SHA both pass it without a
/// word. Resolving each ref against the GitHub API is the only thing that
/// answers the question.
///
/// Local actions (`uses: ./...`) are skipped: they are files in this
/// repository, and a missing one is caught by the workflow that calls it.
///
/// Usage:
///   make check-action-pins
///
/// Requires the `gh` CLI, authenticated. In CI, set `GH_TOKEN`.
///
/// Exit codes:
///   0 - Every reference resolves
///   1 - At least one reference does not resolve
///   2 - Error occurred (gh missing, not authenticated, API unreachable)
library;

import 'dart:io';

import 'src/common.dart';

/// `uses: owner/repo@ref` or `uses: owner/repo/path@ref`, with optional quotes
/// and a trailing `# vX.Y.Z` comment.
final _usesPattern = RegExp(
  r'''^\s*(?:-\s*)?uses:\s*['"]?([^'"\s#]+)['"]?''',
  multiLine: true,
);

/// A 40-character hex commit SHA, which resolves as a commit rather than a tag.
final _shaPattern = RegExp(r'^[0-9a-f]{40}$');

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    // ignore: avoid_print
    print(
      'Usage: make check-action-pins\n'
      '\n'
      'Resolves every third-party `uses:` reference in .github/workflows and\n'
      '.github/actions against the GitHub API, so a version or SHA that does\n'
      'not exist fails here rather than during a release.\n'
      '\n'
      'Requires an authenticated `gh` CLI (GH_TOKEN in CI).',
    );
    exit(0);
  }

  try {
    if (!await commandExists('gh')) {
      logError(
        'The gh CLI is required to resolve action references. '
        'Install it (https://cli.github.com) or set GH_TOKEN in CI.',
      );
      exit(2);
    }

    final references = _collectReferences();
    if (references.isEmpty) {
      logError('No third-party action references found — is the glob wrong?');
      exit(2);
    }

    logStep('Resolving ${references.length} action reference(s)...');

    var failures = 0;
    // Sorted so the log reads the same way twice, and de-duplicated so a pin
    // used by five workflows costs one API call.
    for (final reference in references.keys.toList()..sort()) {
      final result = await _resolve(reference);
      final where = references[reference]!.join(', ');
      switch (result) {
        case _Resolution.ok:
          logInfo('$reference — OK');
        case _Resolution.missing:
          logError('$reference does not exist (referenced by $where)');
          failures++;
        case _Resolution.inconclusive:
          // A rate limit or a network blip must not read as "the pin is fine".
          logError(
            '$reference could not be resolved (referenced by $where). '
            'Check that gh is authenticated and the API is reachable.',
          );
          exit(2);
      }
    }

    if (failures > 0) {
      logError(
        '$failures action reference(s) do not exist. Fix the `uses:` lines '
        'above — nothing else in CI checks them before a release.',
      );
      exit(1);
    }
    logSuccess('Every action reference resolves.');
  } catch (e) {
    logError('$e');
    exit(2);
  }
}

enum _Resolution { ok, missing, inconclusive }

/// Every `owner/repo@ref` in the workflows and composite actions, mapped to the
/// files that reference it.
Map<String, Set<String>> _collectReferences() {
  final packageRoot = getPackageDir().path;
  final references = <String, Set<String>>{};

  for (final dir in ['.github/workflows', '.github/actions']) {
    final directory = Directory('$packageRoot/$dir');
    if (!directory.existsSync()) continue;

    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.yml') && !entity.path.endsWith('.yaml')) {
        continue;
      }

      final relative = entity.path.substring(packageRoot.length + 1);
      for (final match in _usesPattern.allMatches(entity.readAsStringSync())) {
        final reference = match.group(1)!;
        // Local actions and reusable workflows live in this repository.
        if (reference.startsWith('./') || reference.startsWith('docker://')) {
          continue;
        }
        if (!reference.contains('@')) continue;
        references.putIfAbsent(reference, () => {}).add(relative);
      }
    }
  }
  return references;
}

/// Ask GitHub whether [reference] resolves, as a tag, a branch or a commit.
Future<_Resolution> _resolve(String reference) async {
  final at = reference.lastIndexOf('@');
  final ref = reference.substring(at + 1);
  // `owner/repo/path/to/action@ref` — the action lives in a subdirectory of the
  // repository, and it is the repository that has to be asked.
  final parts = reference.substring(0, at).split('/');
  if (parts.length < 2) return _Resolution.missing;
  final repo = '${parts[0]}/${parts[1]}';

  final endpoints = _shaPattern.hasMatch(ref)
      ? ['repos/$repo/commits/$ref']
      : ['repos/$repo/git/ref/tags/$ref', 'repos/$repo/git/ref/heads/$ref'];

  var sawFailure = false;
  for (final endpoint in endpoints) {
    // Process.run captures both streams, so gh's own `gh: Not Found (HTTP 404)`
    // never reaches the log. That matters: printed, it lands above this
    // script's own message and reads like the tool crashed rather than like a
    // pin that does not resolve.
    final result = await Process.run('gh', ['api', endpoint, '--silent']);
    if (result.exitCode == 0) return _Resolution.ok;
    sawFailure = true;
    // gh reports a missing ref on stderr; anything else (auth, rate limit,
    // network) must not be read as "missing".
    final stderr = '${result.stderr}'.toLowerCase();
    if (!stderr.contains('not found') && !stderr.contains('404')) {
      return _Resolution.inconclusive;
    }
  }
  return sawFailure ? _Resolution.missing : _Resolution.inconclusive;
}
