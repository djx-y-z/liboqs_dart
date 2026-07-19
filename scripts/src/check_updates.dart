/// Check for liboqs updates and optionally update pubspec.yaml
///
/// This module provides functionality to:
/// - Check for new liboqs releases on GitHub
/// - Compare versions using semver
/// - Update liboqs.native_version in pubspec.yaml

import 'dart:convert';
import 'dart:io';

import 'common.dart';

/// Result of version check
class UpdateCheckResult {
  final String currentVersion;
  final String latestVersion;
  final bool needsUpdate;
  final bool isPrerelease;
  final String? releaseUrl;

  UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.needsUpdate,
    required this.isPrerelease,
    this.releaseUrl,
  });

  Map<String, dynamic> toJson() => {
    'current_version': currentVersion,
    'latest_version': latestVersion,
    'needs_update': needsUpdate,
    'is_prerelease': isPrerelease,
    'release_url': releaseUrl,
  };
}

/// Check for liboqs updates
Future<UpdateCheckResult> checkForUpdates({
  String? targetVersion,
  bool silent = false,
}) async {
  // Read current version
  final currentVersion = getLiboqsVersion();
  if (!silent) logInfo('Current liboqs version: $currentVersion');

  // Get latest version from GitHub
  String latestVersion;
  bool isPrerelease;
  String? releaseUrl;

  if (targetVersion != null && targetVersion.isNotEmpty) {
    latestVersion = targetVersion;
    isPrerelease = latestVersion.contains('-');
    if (!silent) logInfo('Using specified version: $latestVersion');
  } else {
    if (!silent) logStep('Fetching latest liboqs release from GitHub...');
    final result = await _fetchLatestRelease();
    latestVersion = result['version']!;
    isPrerelease = result['isPrerelease'] == 'true';
    releaseUrl = result['releaseUrl'];
    if (!silent) {
      logInfo('Latest version: $latestVersion (prerelease: $isPrerelease)');
    }
  }

  // Compare versions
  final needsUpdate = _compareVersions(latestVersion, currentVersion);

  if (!silent) {
    if (needsUpdate) {
      logInfo('Update available: $currentVersion -> $latestVersion');
    } else {
      logInfo('Already up to date');
    }
  }

  return UpdateCheckResult(
    currentVersion: currentVersion,
    latestVersion: latestVersion,
    needsUpdate: needsUpdate,
    isPrerelease: isPrerelease,
    releaseUrl:
        releaseUrl ??
        'https://github.com/open-quantum-safe/liboqs/releases/tag/$latestVersion',
  );
}

/// Fetch latest release info from GitHub API
Future<Map<String, String>> _fetchLatestRelease() async {
  final result = await Process.run('curl', [
    '-s',
    'https://api.github.com/repos/open-quantum-safe/liboqs/releases',
  ]);

  if (result.exitCode != 0) {
    throw Exception('Failed to fetch releases from GitHub');
  }

  final releases = jsonDecode(result.stdout as String) as List;
  if (releases.isEmpty) {
    throw Exception('No releases found');
  }

  final latest = releases[0] as Map<String, dynamic>;
  final version = latest['tag_name'] as String;
  // The tag name is attacker-controlled upstream data that ends up in
  // GITHUB_OUTPUT and, from there, in workflow shell commands and branch
  // names. Reject anything that is not a plain semver-ish tag.
  if (!RegExp(r'^v?\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$').hasMatch(version)) {
    throw Exception('Refusing unexpected upstream tag_name format: "$version"');
  }
  final isPrerelease = latest['prerelease'] as bool;
  final htmlUrl = latest['html_url'] as String?;

  return {
    'version': version,
    'isPrerelease': isPrerelease.toString(),
    'releaseUrl': htmlUrl ?? '',
  };
}

/// Number of semver components (major.minor.patch)
const _semverComponents = 3;

/// Compare two semver versions, returns true if v1 > v2
bool _compareVersions(String v1, String v2) {
  // Remove 'v' prefix and pre-release suffix for base comparison
  final v1Base = v1.replaceFirst(RegExp(r'^v'), '').split('-')[0];
  final v2Base = v2.replaceFirst(RegExp(r'^v'), '').split('-')[0];

  List<int> v1Parts;
  List<int> v2Parts;
  try {
    v1Parts = v1Base.split('.').map(int.parse).toList();
    v2Parts = v2Base.split('.').map(int.parse).toList();
  } catch (e) {
    throw Exception('Invalid version format: v1=$v1, v2=$v2. Error: $e');
  }

  // Pad with zeros if needed
  while (v1Parts.length < _semverComponents) {
    v1Parts.add(0);
  }
  while (v2Parts.length < _semverComponents) {
    v2Parts.add(0);
  }

  // Compare major.minor.patch
  for (var i = 0; i < _semverComponents; i++) {
    if (v1Parts[i] > v2Parts[i]) return true;
    if (v1Parts[i] < v2Parts[i]) return false;
  }

  // Base versions are equal, check pre-release
  // If v1 has no suffix and v2 has suffix, v1 is newer (stable > rc)
  // If both have same base but different suffix, consider them equal for update purposes
  return false;
}

/// Update liboqs.native_version in pubspec.yaml
Future<void> updateVersionFiles({
  required String newLiboqsVersion,
  bool silent = false,
}) async {
  final packageDir = getPackageDir();

  // Check if native_version is actually changing
  final currentLiboqsVersion = getLiboqsVersion();
  final versionChanged = currentLiboqsVersion != newLiboqsVersion;

  if (!silent) logStep('Updating pubspec.yaml...');
  final pubspecFile = File('${packageDir.path}/pubspec.yaml');
  var pubspecContent = pubspecFile.readAsStringSync();

  // Update liboqs.native_version
  pubspecContent = pubspecContent.replaceFirstMapped(
    RegExp(
      r'(^liboqs:\s*\n(?:.*\n)*?\s*native_version:\s*)"?[^"\s\n]+"?',
      multiLine: true,
    ),
    (match) => '${match.group(1)}"$newLiboqsVersion"',
  );

  // Reset liboqs.native_build to 1 if version changed
  if (versionChanged) {
    pubspecContent = pubspecContent.replaceFirstMapped(
      RegExp(
        r'(^liboqs:\s*\n(?:.*\n)*?\s*native_build:\s*)\d+',
        multiLine: true,
      ),
      (match) => '${match.group(1)}1',
    );
  }

  await pubspecFile.writeAsString(pubspecContent);
  if (!silent) {
    logInfo('Updated liboqs.native_version: $newLiboqsVersion');
    if (versionChanged) logInfo('Reset liboqs.native_build: 1');
  }
}

/// Print update summary
void printUpdateSummary({
  required UpdateCheckResult checkResult,
  required bool updated,
}) {
  print('');
  print('========================================');
  print('  Update Check Summary');
  print('========================================');
  print('');
  print('liboqs:');
  print('  Current: ${checkResult.currentVersion}');
  print('  Latest:  ${checkResult.latestVersion}');
  print('  Update:  ${checkResult.needsUpdate ? "Available" : "Up to date"}');

  if (checkResult.isPrerelease) {
    print('  Note:    Pre-release version');
  }

  print('');
  if (updated) {
    print('File updated:');
    print('  - pubspec.yaml (liboqs.native_version, liboqs.native_build)');
    print('');
    print('Next steps:');
    print('  1. Run: make regen (if API changed)');
    print('  2. Update README.md badge');
    print('  3. Update CHANGELOG.md');
    print('  4. Run tests: make test');
    print('  5. Commit and push (PR -> main)');
    print('  6. After merge: make release-native (tags liboqs-<fullVersion>,');
    print('     which triggers the native build)');
  } else if (checkResult.needsUpdate) {
    print('To update, run:');
    print('  make check ARGS="--update"');
  }
  print('');
}

/// Output results as JSON (for CI integration)
void printJsonOutput({
  required UpdateCheckResult checkResult,
  required bool updated,
}) {
  final output = <String, dynamic>{
    'liboqs': checkResult.toJson(),
    'updated': updated,
  };

  // Pretty print JSON
  const encoder = JsonEncoder.withIndent('  ');
  print(encoder.convert(output));
}

/// Perform full update check
///
/// This is the main entry point that orchestrates the update process:
/// 1. Check for new liboqs version
/// 2. Optionally update pubspec.yaml
///
/// Returns a record with all results for further processing.
Future<({UpdateCheckResult checkResult, bool updated})> performUpdateCheck({
  String? targetVersion,
  bool doUpdate = false,
  bool force = false,
  bool silent = false,
}) async {
  // Step 1: Check for updates
  final checkResult = await checkForUpdates(
    targetVersion: targetVersion,
    silent: silent,
  );

  // Step 2: Update files if requested
  if (doUpdate && (checkResult.needsUpdate || force)) {
    await updateVersionFiles(
      newLiboqsVersion: checkResult.latestVersion,
      silent: silent,
    );
  }

  final wasUpdated = doUpdate && (checkResult.needsUpdate || force);

  return (checkResult: checkResult, updated: wasUpdated);
}

/// Write outputs to GitHub Actions output file
///
/// This allows the workflow to access the results without parsing JSON.
Future<void> writeGitHubOutputs({
  required UpdateCheckResult checkResult,
  required bool updated,
}) async {
  final githubOutput = Platform.environment['GITHUB_OUTPUT'];
  if (githubOutput == null) {
    return; // Not running in GitHub Actions
  }

  final file = File(githubOutput);
  final buffer = StringBuffer();

  // Check results
  buffer.writeln('current_version=${checkResult.currentVersion}');
  buffer.writeln('latest_version=${checkResult.latestVersion}');
  buffer.writeln('needs_update=${checkResult.needsUpdate}');
  buffer.writeln('is_prerelease=${checkResult.isPrerelease}');
  buffer.writeln('release_url=${checkResult.releaseUrl ?? ""}');
  buffer.writeln('updated=$updated');

  await file.writeAsString(buffer.toString(), mode: FileMode.append);
}
