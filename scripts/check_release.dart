#!/usr/bin/env dart

/// Check if a GitHub release exists for the current native library version
///
/// Usage:
///   dart run scripts/check_release.dart [--ci]
///
/// Options:
///   --ci    Output results to GITHUB_OUTPUT for CI workflows
///
/// Exit codes:
///   0 - Success (release exists or doesn't exist, result in output)
///   1 - Error (failed to check)
///
/// Output (stdout):
///   version=<native_version>
///   build=<native_build>
///   full_version=<full_version>
///   tag=<tag_name>
///   exists=<true|false>
///   skip=<true|false>

import 'dart:io';

import 'src/common.dart';

Future<void> main(List<String> args) async {
  final ciMode = args.contains('--ci');

  try {
    // Get version info
    final version = getLiboqsVersion();
    final build = getNativeBuild();
    final fullVersion = getFullVersion();
    final tagName = 'liboqs-$fullVersion';

    // Get repository from environment or use default
    final repository =
        Platform.environment['GITHUB_REPOSITORY'] ?? 'djx-y-z/liboqs_dart';

    // Check if release exists. Fail closed: if we cannot tell (API error,
    // unexpected status, network failure), abort rather than reporting
    // exists=false, which would let a build proceed on a wrong assumption.
    final status = await _checkReleaseExists(repository, tagName);
    if (status == _ReleaseStatus.inconclusive) {
      logError(
        'Could not determine whether $tagName exists (GitHub API error or '
        'network failure). Aborting instead of guessing. Re-run the workflow, '
        'or verify the release manually.',
      );
      exit(1);
    }
    final exists = status == _ReleaseStatus.exists;

    // Output results
    final outputs = {
      'version': version,
      'build': build,
      'full_version': fullVersion,
      'tag': tagName,
      'exists': exists.toString(),
      'skip': exists.toString(),
    };

    if (ciMode) {
      // Write to GITHUB_OUTPUT
      final githubOutput = Platform.environment['GITHUB_OUTPUT'];
      if (githubOutput != null) {
        final file = File(githubOutput);
        final buffer = StringBuffer();
        for (final entry in outputs.entries) {
          buffer.writeln('${entry.key}=${entry.value}');
        }
        await file.writeAsString(buffer.toString(), mode: FileMode.append);
      }

      // Surface a skipped run in the workflow UI: a green run that built
      // nothing is easy to misread as "rebuilt".
      if (exists) {
        print(
          '::notice::Release $tagName already exists - all build jobs will '
          'be skipped. To rebuild, delete the release and its tag first: '
          'gh release delete $tagName --cleanup-tag --yes',
        );
      }

      // Also print for logging
      _printResults(outputs, exists);
    } else {
      // Print to stdout
      for (final entry in outputs.entries) {
        print('${entry.key}=${entry.value}');
      }
    }

    exit(0);
  } catch (e) {
    logError('Failed to check release: $e');
    exit(1);
  }
}

/// Three-state result of the release-existence probe. `inconclusive` (unexpected
/// status, network error) is treated as fail-closed by the caller.
enum _ReleaseStatus { exists, missing, inconclusive }

/// Check if a GitHub release with the given tag exists
Future<_ReleaseStatus> _checkReleaseExists(
  String repository,
  String tagName,
) async {
  final url = 'https://api.github.com/repos/$repository/releases/tags/$tagName';

  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));

    // Add GitHub token if available (for higher rate limits)
    final token =
        Platform.environment['GITHUB_TOKEN'] ??
        Platform.environment['GH_TOKEN'];
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    request.headers.set('Accept', 'application/vnd.github.v3+json');
    request.headers.set('User-Agent', 'liboqs-dart-release-checker');

    final response = await request.close();
    await response.drain<void>();

    if (response.statusCode == 200) {
      return _ReleaseStatus.exists;
    } else if (response.statusCode == 404) {
      return _ReleaseStatus.missing;
    }
    logWarn('Unexpected response from GitHub API: ${response.statusCode}');
    return _ReleaseStatus.inconclusive;
  } catch (e) {
    logWarn('Failed to check GitHub API: $e');
    return _ReleaseStatus.inconclusive;
  } finally {
    client.close();
  }
}

void _printResults(Map<String, String> outputs, bool exists) {
  print('');
  print('========================================');
  print('  Release Check Results');
  print('========================================');
  print('');
  print('  Version:      ${outputs['version']}');
  print('  Build:        ${outputs['build']}');
  print('  Full Version: ${outputs['full_version']}');
  print('  Tag:          ${outputs['tag']}');
  print('');
  if (exists) {
    print('  ${Colors.colorize('✓ Release exists', Colors.green)}');
    print('  ${Colors.colorize('→ Build will be SKIPPED', Colors.yellow)}');
  } else {
    print('  ${Colors.colorize('✗ Release does not exist', Colors.yellow)}');
    print('  ${Colors.colorize('→ Build will PROCEED', Colors.green)}');
  }
  print('');
}
