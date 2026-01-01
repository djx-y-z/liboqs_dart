/// Check for liboqs updates and optionally update local files
///
/// This module provides functionality to:
/// - Check for new liboqs releases on GitHub
/// - Compare versions using semver
/// - Analyze release notes with AI (optional)
/// - Update pubspec.yaml (version, liboqs.native_version, liboqs.native_build) and CHANGELOG.md

import 'dart:convert';
import 'dart:io';

import 'ai_analysis.dart';
import 'common.dart';

// Re-export for convenience
export 'ai_analysis.dart' show AiAnalysisResult;

/// Result of version check
class UpdateCheckResult {
  final String currentVersion;
  final String latestVersion;
  final bool needsUpdate;
  final bool isPrerelease;
  final String? releaseNotes;
  final String? releaseUrl;

  UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.needsUpdate,
    required this.isPrerelease,
    this.releaseNotes,
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

/// Result of package version calculation
class PackageVersionResult {
  final String currentVersion;
  final String newVersion;
  final String bumpType;
  final bool isPrerelease;

  PackageVersionResult({
    required this.currentVersion,
    required this.newVersion,
    required this.bumpType,
    required this.isPrerelease,
  });

  Map<String, dynamic> toJson() => {
    'current_version': currentVersion,
    'new_version': newVersion,
    'bump_type': bumpType,
    'is_prerelease': isPrerelease,
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
  String? releaseNotes;
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
    releaseNotes = result['releaseNotes'];
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
    releaseNotes: releaseNotes,
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
  final isPrerelease = latest['prerelease'] as bool;
  final body = latest['body'] as String? ?? 'No release notes available';
  final htmlUrl = latest['html_url'] as String?;

  return {
    'version': version,
    'isPrerelease': isPrerelease.toString(),
    'releaseNotes': body,
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
  while (v1Parts.length < _semverComponents) v1Parts.add(0);
  while (v2Parts.length < _semverComponents) v2Parts.add(0);

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

/// Calculate new package version based on version bump type
PackageVersionResult calculatePackageVersion({
  required String currentLiboqs,
  required String newLiboqs,
  required bool isPrerelease,
  String bumpType = 'minor',
  bool silent = false,
}) {
  final packageDir = getPackageDir();

  // Read current package version from pubspec.yaml
  final pubspecFile = File('${packageDir.path}/pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  final versionMatch = RegExp(
    r'^version:\s*(.+)$',
    multiLine: true,
  ).firstMatch(pubspecContent);

  if (versionMatch == null) {
    throw Exception('Could not find version in pubspec.yaml');
  }

  final currentPkgVersion = versionMatch.group(1)!.trim();
  if (!silent) logInfo('Current package version: $currentPkgVersion');

  // Extract base versions
  final currentLiboqsBase = currentLiboqs
      .replaceFirst(RegExp(r'^v'), '')
      .split('-')[0];
  final newLiboqsBase = newLiboqs.replaceFirst(RegExp(r'^v'), '').split('-')[0];
  final ourBaseVersion = currentPkgVersion.split('-')[0];

  // Parse our version components
  List<int> parts;
  try {
    parts = ourBaseVersion.split('.').map(int.parse).toList();
  } catch (e) {
    throw Exception(
      'Invalid package version format: $currentPkgVersion. Error: $e',
    );
  }
  if (parts.length < _semverComponents) {
    throw Exception(
      'Package version must have at least $_semverComponents components: $currentPkgVersion',
    );
  }
  var major = parts[0];
  var minor = parts[1];
  var patch = parts[2];

  String newVersion;
  String actualBumpType;

  // If same liboqs base version, don't bump (just change RC suffix)
  if (currentLiboqsBase == newLiboqsBase) {
    if (!silent) {
      logInfo('Same base liboqs version - only updating pre-release suffix');
    }
    newVersion = ourBaseVersion;
    actualBumpType = 'none';
  } else {
    // Different base version - need to bump
    actualBumpType = bumpType;
    switch (bumpType) {
      case 'major':
        major++;
        minor = 0;
        patch = 0;
        break;
      case 'minor':
        minor++;
        patch = 0;
        break;
      case 'patch':
        patch++;
        break;
      default:
        minor++;
        patch = 0;
        actualBumpType = 'minor';
    }
    newVersion = '$major.$minor.$patch';
  }

  // Add prerelease suffix if needed
  if (isPrerelease) {
    // Extract suffix from liboqs version (e.g., -rc1, -alpha, -beta)
    final suffixMatch = RegExp(r'-(.+)$').firstMatch(newLiboqs);
    final suffix = suffixMatch?.group(0) ?? '-pre';
    newVersion = '$newVersion$suffix';
  }

  if (!silent)
    logInfo('New package version: $newVersion (bump: $actualBumpType)');

  return PackageVersionResult(
    currentVersion: currentPkgVersion,
    newVersion: newVersion,
    bumpType: actualBumpType,
    isPrerelease: isPrerelease,
  );
}

/// Update all version files
Future<void> updateVersionFiles({
  required String newLiboqsVersion,
  required String newPackageVersion,
  required String bumpType,
  required bool isPrerelease,
  String? releaseUrl,
  bool silent = false,
  bool skipChangelog = false,
  String? customChangelogEntry,
}) async {
  final packageDir = getPackageDir();

  // Check if native_version is actually changing
  final currentLiboqsVersion = getLiboqsVersion();
  final versionChanged = currentLiboqsVersion != newLiboqsVersion;

  // 1. Update pubspec.yaml (package version, liboqs.native_version, liboqs.native_build)
  if (!silent) logStep('Updating pubspec.yaml...');
  final pubspecFile = File('${packageDir.path}/pubspec.yaml');
  var pubspecContent = pubspecFile.readAsStringSync();

  // Update package version
  pubspecContent = pubspecContent.replaceFirst(
    RegExp(r'^version:\s*.+$', multiLine: true),
    'version: $newPackageVersion',
  );

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
    if (!silent) logInfo('Reset liboqs.native_build to 1 (version changed)');
  }

  await pubspecFile.writeAsString(pubspecContent);
  if (!silent) {
    logInfo('Updated pubspec.yaml:');
    logInfo('  - version: $newPackageVersion');
    logInfo('  - liboqs.native_version: $newLiboqsVersion');
    if (versionChanged) logInfo('  - liboqs.native_build: 1');
  }

  // 2. Update CHANGELOG.md (unless skipped for CI)
  if (!skipChangelog) {
    if (!silent) logStep('Updating CHANGELOG.md...');
    await _updateChangelog(
      packageDir: packageDir,
      newVersion: newPackageVersion,
      newLiboqs: newLiboqsVersion,
      bumpType: bumpType,
      isPrerelease: isPrerelease,
      releaseUrl: releaseUrl,
      customEntry: customChangelogEntry,
    );
    if (!silent) logInfo('Updated CHANGELOG.md');
  } else {
    if (!silent) logInfo('Skipping CHANGELOG.md (--no-changelog)');
  }
}

/// Update CHANGELOG.md with new entry
Future<void> _updateChangelog({
  required Directory packageDir,
  required String newVersion,
  required String newLiboqs,
  required String bumpType,
  required bool isPrerelease,
  String? releaseUrl,
  String? customEntry,
}) async {
  final changelogFile = File('${packageDir.path}/CHANGELOG.md');
  final currentContent = changelogFile.readAsStringSync();

  // Determine section header based on bump type
  String sectionHeader;
  switch (bumpType) {
    case 'major':
      sectionHeader = '### Breaking Changes';
      break;
    case 'minor':
      sectionHeader = '### Added';
      break;
    case 'patch':
      sectionHeader = '### Fixed';
      break;
    default:
      sectionHeader = '### Changed';
  }

  // Build prerelease note
  final prereleaseNote = isPrerelease
      ? '\n> **Pre-release**: This version includes a release candidate of liboqs. Use with caution in production.\n'
      : '';

  // Build release URL
  final releaseLink =
      releaseUrl ??
      'https://github.com/open-quantum-safe/liboqs/releases/tag/$newLiboqs';

  // Use custom entry from AI or default
  String changelogContent;
  if (customEntry != null && customEntry.trim().isNotEmpty) {
    changelogContent = customEntry.trim();
  } else {
    changelogContent = '- Updated liboqs native library to $newLiboqs';
  }

  // Create new entry
  final newEntry =
      '''
## $newVersion
$prereleaseNote
$sectionHeader
$changelogContent
- See [liboqs $newLiboqs release notes]($releaseLink)

''';

  // Prepend to changelog
  final newContent = newEntry + currentContent;
  await changelogFile.writeAsString(newContent);
}

/// Print update summary
void printUpdateSummary({
  required UpdateCheckResult checkResult,
  required PackageVersionResult? packageResult,
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

  if (packageResult != null) {
    print('');
    print('Package:');
    print('  Current: ${packageResult.currentVersion}');
    print('  New:     ${packageResult.newVersion}');
    print('  Bump:    ${packageResult.bumpType}');
  }

  print('');
  if (updated) {
    print('Files updated:');
    print(
      '  - pubspec.yaml (version, liboqs.native_version, liboqs.native_build)',
    );
    print('  - CHANGELOG.md');
    print('');
    print('Next steps:');
    print('  1. Review changes: git diff');
    print('  2. Run tests: fvm dart test');
    print('  3. Commit and push to trigger CI build');
  } else if (checkResult.needsUpdate) {
    print('To update, run:');
    print('  fvm dart run scripts/check_updates.dart --update');
  }
  print('');
}

/// Output results as JSON (for CI integration)
void printJsonOutput({
  required UpdateCheckResult checkResult,
  required PackageVersionResult? packageResult,
  required bool updated,
  AiAnalysisResult? aiResult,
}) {
  final output = <String, dynamic>{
    'liboqs': checkResult.toJson(),
    'updated': updated,
  };

  if (packageResult != null) {
    output['package'] = packageResult.toJson();
  }

  if (aiResult != null) {
    output['ai_analysis'] = aiResult.toJson();
  }

  // Pretty print JSON
  final encoder = JsonEncoder.withIndent('  ');
  print(encoder.convert(output));
}

/// Perform full update check with optional AI analysis
///
/// This is the main entry point that orchestrates the entire update process:
/// 1. Check for new liboqs version
/// 2. Optionally analyze release notes with AI
/// 3. Calculate new package version
/// 4. Optionally update files
///
/// Returns a record with all results for further processing.
Future<({
  UpdateCheckResult checkResult,
  PackageVersionResult? packageResult,
  AiAnalysisResult? aiResult,
  bool updated,
})> performUpdateCheck({
  String? targetVersion,
  bool doUpdate = false,
  bool force = false,
  bool useAi = false,
  String? githubToken,
  String bumpType = 'minor',
  bool skipChangelog = false,
  bool silent = false,
}) async {
  // Step 1: Check for updates
  final checkResult = await checkForUpdates(
    targetVersion: targetVersion,
    silent: silent,
  );

  PackageVersionResult? packageResult;
  AiAnalysisResult? aiResult;

  if (checkResult.needsUpdate || force) {
    // Step 2: AI analysis (if enabled and token available)
    if (useAi && githubToken != null && githubToken.isNotEmpty) {
      if (!silent) {
        logStep('Performing AI analysis of release notes...');
      }

      // Fetch release notes if not already available
      String? releaseNotes = checkResult.releaseNotes;
      if (releaseNotes == null || releaseNotes.isEmpty) {
        releaseNotes = await _fetchReleaseNotes(checkResult.latestVersion);
      }

      if (releaseNotes != null && releaseNotes.isNotEmpty) {
        aiResult = await analyzeReleaseNotes(
          token: githubToken,
          releaseNotes: releaseNotes,
          currentVersion: checkResult.currentVersion,
          newVersion: checkResult.latestVersion,
          silent: silent,
        );

        if (aiResult != null && !silent) {
          logInfo('AI recommends: ${aiResult.versionBump} bump');
        }
      }
    } else if (useAi && !silent) {
      logWarning('AI analysis requested but no GITHUB_TOKEN available');
    }

    // Step 3: Determine bump type (AI recommendation or manual)
    final effectiveBumpType = aiResult?.versionBump ?? bumpType;

    // Step 4: Calculate new package version
    packageResult = calculatePackageVersion(
      currentLiboqs: checkResult.currentVersion,
      newLiboqs: checkResult.latestVersion,
      isPrerelease: checkResult.isPrerelease,
      bumpType: effectiveBumpType,
      silent: silent,
    );

    // Step 5: Update files if requested
    if (doUpdate) {
      // Use AI-generated changelog if available
      final changelogEntry = aiResult?.changelogEntry;

      await updateVersionFiles(
        newLiboqsVersion: checkResult.latestVersion,
        newPackageVersion: packageResult.newVersion,
        bumpType: packageResult.bumpType,
        isPrerelease: checkResult.isPrerelease,
        releaseUrl: checkResult.releaseUrl,
        silent: silent,
        skipChangelog: skipChangelog,
        customChangelogEntry: changelogEntry,
      );
    }
  }

  final wasUpdated = doUpdate && (checkResult.needsUpdate || force);

  return (
    checkResult: checkResult,
    packageResult: packageResult,
    aiResult: aiResult,
    updated: wasUpdated,
  );
}

/// Fetch release notes for a specific version
Future<String?> _fetchReleaseNotes(String version) async {
  try {
    final result = await Process.run('curl', [
      '-s',
      'https://api.github.com/repos/open-quantum-safe/liboqs/releases/tags/$version',
    ]);

    if (result.exitCode != 0) {
      return null;
    }

    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return json['body'] as String?;
  } catch (e) {
    return null;
  }
}

/// Write outputs to GitHub Actions output file
///
/// This allows the workflow to access the results without parsing JSON.
Future<void> writeGitHubOutputs({
  required UpdateCheckResult checkResult,
  PackageVersionResult? packageResult,
  AiAnalysisResult? aiResult,
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

  // Package results
  if (packageResult != null) {
    buffer.writeln('pkg_current=${packageResult.currentVersion}');
    buffer.writeln('pkg_new=${packageResult.newVersion}');
    buffer.writeln('bump_type=${packageResult.bumpType}');
    buffer.writeln('is_rc=${packageResult.isPrerelease}');
  }

  // AI results
  if (aiResult != null) {
    buffer.writeln('ai_available=true');
    buffer.writeln('ai_model=${aiResult.modelUsed ?? ""}');
    buffer.writeln('ai_bump=${aiResult.versionBump}');
    buffer.writeln('breaking_changes=${aiResult.breakingChanges}');
    buffer.writeln('binding_changes=${aiResult.bindingChanges}');
  } else {
    buffer.writeln('ai_available=false');
  }

  buffer.writeln('updated=$updated');

  await file.writeAsString(buffer.toString(), mode: FileMode.append);
}
