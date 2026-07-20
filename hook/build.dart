// Copyright (c) 2025 liboqs_dart authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

/// Build hook for downloading and bundling liboqs native libraries.
///
/// This hook is automatically invoked by the Dart/Flutter build system
/// when building applications that depend on the liboqs package.
///
/// The hook downloads pre-built native libraries from GitHub Releases
/// based on the target platform and architecture.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

/// Package name for asset registration.
const _packageName = 'liboqs';

/// Asset ID used for looking up the library at runtime.
/// Note: This is just the name part; CodeAsset combines it with package
/// to form the full ID: package:liboqs/liboqs
const _assetId = 'liboqs';

/// GitHub repository for downloading releases.
const _githubRepo = 'djx-y-z/liboqs_dart';

/// Marker written into a version-keyed download cache directory as the LAST
/// step of a successful download+verify+extract. Its absence means the cache
/// entry is incomplete (e.g. an interrupted extraction left a truncated file),
/// so the entry must be re-provisioned rather than reused unverified.
const _cacheCompleteMarker = '.download-complete';

/// Entry point for the build hook.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // Only process if building code assets
    if (!input.config.buildCodeAssets) {
      return;
    }

    final codeConfig = input.config.code;
    final targetOS = codeConfig.targetOS;
    final targetArch = codeConfig.targetArchitecture;
    final iosSdk = targetOS == OS.iOS ? codeConfig.iOS.targetSdk : null;
    final packageRoot = input.packageRoot;

    // Check for skip marker file (used during library building via `make build`)
    // This avoids chicken-and-egg problem when building native libraries
    final skipMarkerUri = packageRoot.resolve('.skip_liboqs_hook');
    final skipFile = File.fromUri(skipMarkerUri);

    // Add marker file as dependency for cache invalidation
    // This ensures hook reruns when marker is created/deleted
    output.dependencies.add(skipMarkerUri);

    if (skipFile.existsSync()) {
      return;
    }

    // For all cases, download from GitHub Releases and bundle with the app
    final fullVersion = await _readFullVersion(packageRoot);
    final assetInfo = _resolveAssetInfo(codeConfig, fullVersion);

    // Output directory for cached downloads.
    //
    // The subdirectory is keyed by the full version AND the full platform
    // variant (see [downloadCacheSubdir]). Both the cache key and the download
    // URL route through the same platform-arch string, so a cached binary can
    // never be reused for a different version or a different platform (notably
    // iOS device vs. simulator, which share targetOS/targetArch on Apple
    // silicon).
    final archSubdir = downloadCacheSubdir(
      version: fullVersion,
      targetOS: targetOS,
      targetArchitecture: targetArch,
      iosSdk: iosSdk,
    );
    final cacheDir = input.outputDirectoryShared.resolve('$archSubdir/');
    final libFile = File.fromUri(cacheDir.resolve(assetInfo.fileName));

    // Download unless the cache entry is COMPLETE. Existence alone is not
    // enough: an interrupted extraction can leave a truncated library that
    // would then be reused (and registered) forever. The completeness marker is
    // written only after a fully verified extraction, so a missing marker
    // re-provisions and heals the entry.
    if (!_isCacheComplete(cacheDir) || !libFile.existsSync()) {
      final baseUrl =
          'https://github.com/$_githubRepo/releases/download/liboqs-$fullVersion';

      // SECURITY: resolve the expected SHA256 before fetching the binary.
      // Fail-closed — if a trusted checksum cannot be obtained the build aborts
      // (unless explicitly overridden via $_allowUnverifiedEnv), so a failed or
      // interfered checksum fetch cannot silently downgrade to running an
      // unverified native library.
      final expectedChecksum = await _resolveExpectedChecksum(
        baseUrl,
        fullVersion,
        assetInfo.archiveFileName,
      );

      await _downloadAndExtract(
        assetInfo.downloadUrl,
        cacheDir,
        assetInfo.archiveFileName,
        assetInfo.fileName,
        expectedChecksum: expectedChecksum,
      );
    }

    // Verify file exists after download
    if (!libFile.existsSync()) {
      throw HookException(
        'Failed to download liboqs library for $targetOS-$targetArch. '
        'File not found: ${libFile.path}',
      );
    }

    // Register native asset (Flutter converts .dylib to Framework for iOS)
    output.assets.code.add(
      CodeAsset(
        package: _packageName,
        name: _assetId,
        linkMode: assetInfo.linkMode,
        file: libFile.uri,
      ),
    );

    // Add dependency on pubspec.yaml for cache invalidation
    // (contains liboqs.native_version and liboqs.native_build)
    output.dependencies.add(packageRoot.resolve('pubspec.yaml'));
  });
}

/// Reads the liboqs version from pubspec.yaml (liboqs.native_version).
Future<String> _readVersion(Uri packageRoot) async {
  final pubspecFile = File.fromUri(packageRoot.resolve('pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    throw HookException('pubspec.yaml not found at ${pubspecFile.path}');
  }

  final content = await pubspecFile.readAsString();

  // Extract the liboqs: block (until next top-level key or EOF)
  final blockMatch = RegExp(
    r'^liboqs:\s*$([\s\S]*?)(?=^\w|\z)',
    multiLine: true,
  ).firstMatch(content);

  if (blockMatch == null) {
    throw HookException('liboqs: block not found in pubspec.yaml');
  }

  final block = blockMatch.group(1) ?? '';

  // Extract native_version from the block
  final versionMatch = RegExp(
    r'native_version:\s*"?([^"\s\n]+)"?',
  ).firstMatch(block);

  if (versionMatch == null) {
    throw HookException('native_version not found in liboqs block');
  }

  return versionMatch.group(1)!.trim();
}

/// Reads the native build number from pubspec.yaml (liboqs.native_build).
Future<String> _readNativeBuild(Uri packageRoot) async {
  final pubspecFile = File.fromUri(packageRoot.resolve('pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    return '1';
  }

  final content = await pubspecFile.readAsString();

  // Extract the liboqs: block
  final blockMatch = RegExp(
    r'^liboqs:\s*$([\s\S]*?)(?=^\w|\z)',
    multiLine: true,
  ).firstMatch(content);

  if (blockMatch == null) {
    return '1';
  }

  final block = blockMatch.group(1) ?? '';

  // Extract native_build from the block
  final buildMatch = RegExp(r'native_build:\s*(\d+)').firstMatch(block);

  return buildMatch?.group(1)?.trim() ?? '1';
}

/// Reads full version (liboqs version + native build).
Future<String> _readFullVersion(Uri packageRoot) async {
  final version = await _readVersion(packageRoot);
  final build = await _readNativeBuild(packageRoot);
  return '$version-$build';
}

/// Information about a native asset for a specific platform.
class _AssetInfo {
  final String downloadUrl;
  final String archiveFileName;
  final String fileName;
  final LinkMode linkMode;

  const _AssetInfo({
    required this.downloadUrl,
    required this.archiveFileName,
    required this.fileName,
    required this.linkMode,
  });
}

/// Resolves asset information for the target platform.
///
/// [fullVersion] is the complete version string including build number,
/// e.g., "0.16.0-1" (liboqs version + native build number).
///
/// The download URL and archive name are built from the same platform-arch
/// string as the cache key ([downloadCacheSubdir]) — both route through
/// [_getPlatformArchName] so they can never drift apart.
_AssetInfo _resolveAssetInfo(CodeConfig codeConfig, String fullVersion) {
  final baseUrl =
      'https://github.com/$_githubRepo/releases/download/liboqs-$fullVersion';
  final targetOS = codeConfig.targetOS;
  final targetArch = codeConfig.targetArchitecture;
  final iosSdk = targetOS == OS.iOS ? codeConfig.iOS.targetSdk : null;

  final platformArch = _getPlatformArchName(targetOS, targetArch, iosSdk);

  // Windows ships as a .zip; every other platform ships as a .tar.gz.
  final archiveExt = targetOS == OS.windows ? 'zip' : 'tar.gz';
  final archiveFileName = 'liboqs-$fullVersion-$platformArch.$archiveExt';

  return _AssetInfo(
    downloadUrl: '$baseUrl/$archiveFileName',
    archiveFileName: archiveFileName,
    // iOS: DynamicLoadingBundled - Flutter automatically converts the .dylib
    // to the Framework format required by the App Store.
    fileName: _libraryFileName(targetOS),
    linkMode: DynamicLoadingBundled(),
  );
}

/// Computes the subdirectory of the shared output directory in which a
/// downloaded native library is cached.
///
/// The shared output directory is reused across build configurations, so the
/// key must include every input that changes which artifact is downloaded: the
/// full [version] (liboqs version + native build) and the full platform variant
/// — notably iOS device vs. simulator, which share [targetOS] and
/// [targetArchitecture] on Apple-silicon hosts.
///
/// Top-level and public so the hook tests can exercise it.
String downloadCacheSubdir({
  required String version,
  required OS targetOS,
  required Architecture targetArchitecture,
  IOSSdk? iosSdk,
}) {
  return '$version-'
      '${_getPlatformArchName(targetOS, targetArchitecture, iosSdk)}';
}

/// Gets the platform-architecture identity used in both the download URL and
/// the cache key.
///
/// For iOS we download architecture-specific .dylib files:
/// - `device-arm64` for physical devices
/// - `simulator-arm64` for Apple Silicon simulators
/// - `simulator-x86_64` for Intel simulators
String _getPlatformArchName(
  OS targetOS,
  Architecture targetArch,
  IOSSdk? iosSdk,
) {
  switch (targetOS) {
    case OS.linux:
      return 'linux-${_linuxArchName(targetArch)}';
    case OS.macOS:
      return 'macos-${_macOSArchName(targetArch)}';
    case OS.windows:
      return 'windows-x86_64';
    case OS.android:
      return 'android-${_androidArchToAbi(targetArch)}';
    case OS.iOS:
      return 'ios-${_iOSTargetName(iosSdk, targetArch)}';
    default:
      throw HookException('Unsupported target OS: $targetOS');
  }
}

/// Returns the extracted native library filename for the target OS.
String _libraryFileName(OS targetOS) {
  switch (targetOS) {
    case OS.linux:
    case OS.android:
      return 'liboqs.so';
    case OS.macOS:
    case OS.iOS:
      return 'liboqs.dylib';
    case OS.windows:
      return 'oqs.dll';
    default:
      throw HookException('Unsupported target OS: $targetOS');
  }
}

/// Converts Dart Architecture to Android ABI name.
String _androidArchToAbi(Architecture arch) {
  switch (arch) {
    case Architecture.arm64:
      return 'arm64-v8a';
    case Architecture.arm:
      return 'armeabi-v7a';
    case Architecture.x64:
      return 'x86_64';
    default:
      throw HookException('Unsupported Android architecture: $arch');
  }
}

/// Converts Dart Architecture to macOS architecture name.
String _macOSArchName(Architecture arch) {
  switch (arch) {
    case Architecture.arm64:
      return 'arm64';
    case Architecture.x64:
      return 'x86_64';
    default:
      throw HookException('Unsupported macOS architecture: $arch');
  }
}

/// Converts Dart Architecture to Linux architecture name.
String _linuxArchName(Architecture arch) {
  switch (arch) {
    case Architecture.arm64:
      return 'arm64';
    case Architecture.x64:
      return 'x86_64';
    default:
      throw HookException('Unsupported Linux architecture: $arch');
  }
}

/// Determines iOS target name based on the iOS SDK and architecture.
///
/// For iOS, we need to determine if we're building for device or simulator,
/// and which architecture. iOS simulators use the iphonesimulator SDK,
/// devices use the iphoneos SDK.
String _iOSTargetName(IOSSdk? iosSdk, Architecture arch) {
  final isSimulator = iosSdk == IOSSdk.iPhoneSimulator;

  if (isSimulator) {
    // Simulator: can be arm64 (Apple Silicon) or x86_64 (Intel)
    switch (arch) {
      case Architecture.arm64:
        return 'simulator-arm64';
      case Architecture.x64:
        return 'simulator-x86_64';
      default:
        throw HookException('Unsupported iOS simulator architecture: $arch');
    }
  } else {
    // Device: always arm64
    if (arch != Architecture.arm64) {
      throw HookException(
        'Unsupported iOS device architecture: $arch (only arm64 is supported)',
      );
    }
    return 'device-arm64';
  }
}

/// Downloads and extracts the native library archive with SHA256 verification.
///
/// [expectedChecksum] is the expected SHA256 hash of the archive.
/// If null, verification is skipped (not recommended for production).
Future<void> _downloadAndExtract(
  String url,
  Uri outputDir,
  String archiveFileName,
  String libFileName, {
  String? expectedChecksum,
}) async {
  final outDir = Directory.fromUri(outputDir);
  await outDir.create(recursive: true);

  final archiveFile = File('${outDir.path}/$archiveFileName');

  // Download with retry
  await _downloadWithRetry(url, archiveFile);

  // Verify SHA256 checksum if provided
  if (expectedChecksum != null) {
    await _verifyChecksum(archiveFile, expectedChecksum, archiveFileName);
  }

  // Extract based on format
  if (url.endsWith('.zip')) {
    await _extractZip(archiveFile, outDir);
  } else {
    await _extractTarGz(archiveFile, outDir);
  }

  // Clean up archive
  if (archiveFile.existsSync()) {
    await archiveFile.delete();
  }

  // Verify extraction
  final libFile = File('${outDir.path}/$libFileName');
  if (!libFile.existsSync()) {
    throw HookException(
      'Extraction failed: $libFileName not found in archive from $url',
    );
  }

  // Mark the cache entry complete only now — after a verified, fully extracted
  // archive. A crash before this point leaves the marker absent, so the next
  // build re-provisions instead of reusing a truncated file.
  _markCacheComplete(outputDir);
}

/// Whether [cacheDir] holds a fully provisioned download (see
/// [_cacheCompleteMarker]).
bool _isCacheComplete(Uri cacheDir) =>
    File.fromUri(cacheDir.resolve(_cacheCompleteMarker)).existsSync();

/// Records that [cacheDir] was fully provisioned. Best-effort: a write failure
/// must not fail the build (the next run simply re-provisions).
void _markCacheComplete(Uri cacheDir) {
  try {
    File.fromUri(
      cacheDir.resolve(_cacheCompleteMarker),
    ).writeAsStringSync('ok\n');
  } catch (_) {
    // Non-fatal.
  }
}

/// Downloads a file with retry logic.
Future<void> _downloadWithRetry(
  String url,
  File outputFile, {
  int maxRetries = 3,
  Duration retryDelay = const Duration(seconds: 2),
}) async {
  final client = HttpClient();
  Exception? lastError;

  try {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        if (response.statusCode == 200) {
          final sink = outputFile.openWrite();
          await response.pipe(sink);
          return;
        } else if (response.statusCode == 404) {
          throw HookException(
            'Native library not found at $url (HTTP 404). '
            'Ensure GitHub Release exists with the correct version.',
          );
        } else if (response.statusCode >= 500 || response.statusCode == 429) {
          // Transient server-side/rate-limit response — let the retry loop
          // below handle it (plain Exception is caught and retried; a
          // HookException would be rethrown immediately and skip the retries).
          await response.drain<void>();
          throw Exception('Transient HTTP ${response.statusCode} from $url');
        } else {
          throw HookException(
            'Failed to download from $url: HTTP ${response.statusCode}',
          );
        }
      } on HookException {
        rethrow;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay * attempt);
        }
      }
    }
  } finally {
    client.close();
  }

  throw HookException(
    'Failed to download from $url after $maxRetries attempts. '
    'Last error: $lastError',
  );
}

/// Extracts a tar.gz archive.
Future<void> _extractTarGz(File archive, Directory outDir) async {
  final result = await Process.run('tar', [
    '-xzf',
    archive.path,
    '-C',
    outDir.path,
  ]);
  if (result.exitCode != 0) {
    throw HookException('Failed to extract tar.gz archive: ${result.stderr}');
  }
}

/// Extracts a zip archive.
Future<void> _extractZip(File archive, Directory outDir) async {
  ProcessResult result;

  if (Platform.isWindows) {
    result = await Process.run('powershell', [
      '-Command',
      'Expand-Archive',
      '-Path',
      archive.path,
      '-DestinationPath',
      outDir.path,
      '-Force',
    ]);
  } else {
    result = await Process.run('unzip', [
      '-o',
      archive.path,
      '-d',
      outDir.path,
    ]);
  }

  if (result.exitCode != 0) {
    throw HookException('Failed to extract zip archive: ${result.stderr}');
  }
}

/// Environment variable that downgrades a missing/unfetchable checksum from a
/// hard build failure to a warning. Unset by default, so verification is
/// fail-closed: a network problem or an interfered checksum fetch aborts the
/// build instead of silently loading an unverified native library.
const _allowUnverifiedEnv = 'LIBOQS_ALLOW_UNVERIFIED_DOWNLOAD';

/// Whether the developer has explicitly opted out of checksum verification.
bool _allowUnverifiedDownload() {
  final value = Platform.environment[_allowUnverifiedEnv]?.trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}

/// Resolves the expected SHA256 for [archiveFileName] from the release's
/// checksums file.
///
/// Fail-closed: throws a [HookException] if the checksums file cannot be
/// downloaded or has no entry for the archive, so an unverified binary is never
/// used. Returns `null` (verification skipped, with a warning) only when the
/// [_allowUnverifiedEnv] escape hatch is set.
Future<String?> _resolveExpectedChecksum(
  String baseUrl,
  String fullVersion,
  String archiveFileName,
) async {
  Map<String, String> checksums;
  try {
    checksums = await _downloadChecksums(baseUrl, fullVersion);
  } catch (e) {
    if (_allowUnverifiedDownload()) {
      // ignore: avoid_print
      print(
        'Warning: could not download SHA256 checksums: $e\n'
        '$_allowUnverifiedEnv is set — proceeding WITHOUT verification.',
      );
      return null;
    }
    throw HookException(
      'Refusing to use an unverified native library: failed to download the '
      'SHA256 checksums file for liboqs-$fullVersion.\n'
      'Cause: $e\n'
      'This guards against a corrupted or tampered download. If you are '
      'deliberately building against a release with no checksums file, set '
      '$_allowUnverifiedEnv=1 to override (NOT recommended for production).',
    );
  }

  final expected = checksums[archiveFileName];
  if (expected == null) {
    if (_allowUnverifiedDownload()) {
      // ignore: avoid_print
      print(
        'Warning: no checksum entry for $archiveFileName.\n'
        '$_allowUnverifiedEnv is set — proceeding WITHOUT verification.',
      );
      return null;
    }
    throw HookException(
      'Refusing to use an unverified native library: the checksums file for '
      'liboqs-$fullVersion has no entry for $archiveFileName.\n'
      'Available entries: ${checksums.keys.join(', ')}\n'
      'Set $_allowUnverifiedEnv=1 to override (NOT recommended for production).',
    );
  }
  return expected;
}

/// Downloads and verifies checksums file from GitHub Release.
///
/// Returns a map of filename -> expected SHA256 hash.
Future<Map<String, String>> _downloadChecksums(
  String baseUrl,
  String fullVersion, {
  int maxRetries = 3,
  Duration retryDelay = const Duration(seconds: 2),
}) async {
  final checksumsUrl = '$baseUrl/liboqs-$fullVersion-checksums.sha256';
  final client = HttpClient();
  Object? lastError;

  try {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final request = await client.getUrl(Uri.parse(checksumsUrl));
        final response = await request.close();

        if (response.statusCode == 200) {
          final content = await response
              .transform(systemEncoding.decoder)
              .join();
          return _parseChecksums(content);
        }

        await response.drain<void>();
        // 5xx/429 are transient — fall through to retry. Other codes (404, 4xx)
        // are permanent, so fail fast without burning retries.
        if (response.statusCode < 500 && response.statusCode != 429) {
          throw HookException(
            'Failed to download checksums from $checksumsUrl: '
            'HTTP ${response.statusCode}',
          );
        }
        lastError = 'HTTP ${response.statusCode}';
      } on HookException {
        rethrow;
      } catch (e) {
        lastError = e;
      }

      if (attempt < maxRetries) {
        await Future.delayed(retryDelay * attempt);
      }
    }
  } finally {
    client.close();
  }

  throw HookException(
    'Failed to download checksums from $checksumsUrl after $maxRetries '
    'attempts. Last error: $lastError',
  );
}

/// Parses SHA256 checksums file content.
///
/// Expected format (standard sha256sum output):
/// ```
/// <hash>  <filename>
/// <hash>  <filename>
/// ```
Map<String, String> _parseChecksums(String content) {
  final checksums = <String, String>{};

  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    // Format: "<hash>  <filename>" (two spaces between hash and filename)
    // Also support single space for compatibility
    final match = RegExp(r'^([a-fA-F0-9]{64})\s+(.+)$').firstMatch(trimmed);
    if (match != null) {
      final hash = match.group(1)!.toLowerCase();
      final filename = match.group(2)!;
      checksums[filename] = hash;
    }
  }

  return checksums;
}

/// Computes SHA256 hash of a file.
Future<String> _computeFileSha256(File file) async {
  final bytes = await file.readAsBytes();
  final digest = sha256.convert(bytes);
  return digest.toString();
}

/// Verifies file SHA256 hash against expected value.
///
/// Throws [HookException] if verification fails.
Future<void> _verifyChecksum(
  File file,
  String expectedHash,
  String filename,
) async {
  final actualHash = await _computeFileSha256(file);

  if (actualHash != expectedHash.toLowerCase()) {
    // Delete the corrupted/tampered file
    if (file.existsSync()) {
      await file.delete();
    }
    throw HookException(
      'SHA256 verification failed for $filename!\n'
      'Expected: $expectedHash\n'
      'Actual:   $actualHash\n'
      'This may indicate a corrupted download or supply chain attack. '
      'Please report this issue at https://github.com/$_githubRepo/issues',
    );
  }
}

/// Custom exception for hook errors.
class HookException implements Exception {
  final String message;
  HookException(this.message);

  @override
  String toString() => 'HookException: $message';
}
