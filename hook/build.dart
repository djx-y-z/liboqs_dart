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
import 'package:hooks/hooks.dart';

/// Package name for asset registration.
const _packageName = 'liboqs';

/// Asset ID used for looking up the library at runtime.
/// Note: This is just the name part; CodeAsset combines it with package
/// to form the full ID: package:liboqs/liboqs
const _assetId = 'liboqs';

/// GitHub repository for downloading releases.
const _githubRepo = 'djx-y-z/liboqs_dart';

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
    final version = await _readVersion(packageRoot);
    final assetInfo = _resolveAssetInfo(codeConfig, version);

    // Output directory for cached downloads
    // Use architecture-specific subdirectory for each platform/arch combination
    final archSubdir = '${targetOS.name}-${targetArch.name}';
    final cacheDir = input.outputDirectoryShared.resolve('$archSubdir/');
    final libFile = File.fromUri(cacheDir.resolve(assetInfo.fileName));

    // Download if not cached
    if (!libFile.existsSync()) {
      await _downloadAndExtract(
        assetInfo.downloadUrl,
        cacheDir,
        assetInfo.archiveFileName,
        assetInfo.fileName,
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

    // Add dependency on version file for cache invalidation
    output.dependencies.add(packageRoot.resolve('LIBOQS_VERSION'));
  });
}

/// Reads the liboqs version from LIBOQS_VERSION file.
Future<String> _readVersion(Uri packageRoot) async {
  final versionFile = File.fromUri(packageRoot.resolve('LIBOQS_VERSION'));
  if (!versionFile.existsSync()) {
    throw HookException('LIBOQS_VERSION file not found at ${versionFile.path}');
  }
  return (await versionFile.readAsString()).trim();
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
_AssetInfo _resolveAssetInfo(CodeConfig codeConfig, String version) {
  final baseUrl =
      'https://github.com/$_githubRepo/releases/download/liboqs-$version';
  final targetOS = codeConfig.targetOS;
  final targetArch = codeConfig.targetArchitecture;

  switch (targetOS) {
    case OS.linux:
      return _AssetInfo(
        downloadUrl: '$baseUrl/liboqs-$version-linux-x86_64.tar.gz',
        archiveFileName: 'liboqs-$version-linux-x86_64.tar.gz',
        fileName: 'liboqs.so',
        linkMode: DynamicLoadingBundled(),
      );

    case OS.macOS:
      // Use architecture-specific binaries (Flutter will merge them with lipo)
      final arch = _macOSArchName(targetArch);
      return _AssetInfo(
        downloadUrl: '$baseUrl/liboqs-$version-macos-$arch.tar.gz',
        archiveFileName: 'liboqs-$version-macos-$arch.tar.gz',
        fileName: 'liboqs.dylib',
        linkMode: DynamicLoadingBundled(),
      );

    case OS.windows:
      return _AssetInfo(
        downloadUrl: '$baseUrl/liboqs-$version-windows-x86_64.zip',
        archiveFileName: 'liboqs-$version-windows-x86_64.zip',
        fileName: 'oqs.dll',
        linkMode: DynamicLoadingBundled(),
      );

    case OS.android:
      final abi = _androidArchToAbi(targetArch);
      return _AssetInfo(
        downloadUrl: '$baseUrl/liboqs-$version-android-$abi.tar.gz',
        archiveFileName: 'liboqs-$version-android-$abi.tar.gz',
        fileName: 'liboqs.so',
        linkMode: DynamicLoadingBundled(),
      );

    case OS.iOS:
      // iOS: Use DynamicLoadingBundled - Flutter automatically converts
      // .dylib to Framework format required by App Store.
      //
      // We download architecture-specific .dylib files:
      // - device-arm64 for physical devices
      // - simulator-arm64 for Apple Silicon simulators
      // - simulator-x86_64 for Intel simulators
      final iosTarget = _iOSTargetName(codeConfig, targetArch);
      return _AssetInfo(
        downloadUrl: '$baseUrl/liboqs-$version-ios-$iosTarget.tar.gz',
        archiveFileName: 'liboqs-$version-ios-$iosTarget.tar.gz',
        fileName: 'liboqs.dylib',
        linkMode: DynamicLoadingBundled(),
      );

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

/// Determines iOS target name based on CodeConfig.
///
/// For iOS, we need to determine if we're building for device or simulator,
/// and which architecture. The CodeConfig provides this information.
String _iOSTargetName(CodeConfig codeConfig, Architecture arch) {
  // Check if building for simulator by looking at the iOS SDK
  // iOS simulators use iphonesimulator SDK, devices use iphoneos SDK
  // The CodeConfig.iOS.targetSdk property tells us which one
  final isSimulator = codeConfig.iOS.targetSdk == IOSSdk.iPhoneSimulator;

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

/// Downloads and extracts the native library archive.
Future<void> _downloadAndExtract(
  String url,
  Uri outputDir,
  String archiveFileName,
  String libFileName,
) async {
  final outDir = Directory.fromUri(outputDir);
  await outDir.create(recursive: true);

  final archiveFile = File('${outDir.path}/$archiveFileName');

  // Download with retry
  await _downloadWithRetry(url, archiveFile);

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

/// Custom exception for hook errors.
class HookException implements Exception {
  final String message;
  HookException(this.message);

  @override
  String toString() => 'HookException: $message';
}
