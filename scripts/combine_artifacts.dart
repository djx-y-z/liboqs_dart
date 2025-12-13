#!/usr/bin/env dart

/// Combine build artifacts from CI into final binaries
///
/// This script is used by CI after all platform builds complete.
/// It creates:
///   - macOS Universal Binary (arm64 + x86_64)
///   - iOS XCFramework (device + simulator)
///
/// Usage:
///   dart run scripts/combine_artifacts.dart --artifacts-dir /path/to/artifacts
///
/// Expected artifacts directory structure:
///   artifacts/
///   ├── liboqs-linux-x86_64/liboqs.so
///   ├── liboqs-macos-arm64/liboqs.dylib
///   ├── liboqs-macos-x86_64/liboqs.dylib
///   ├── liboqs-ios-device-arm64/liboqs.a
///   ├── liboqs-ios-simulator-arm64/liboqs.a
///   ├── liboqs-ios-simulator-x86_64/liboqs.a
///   ├── liboqs-android-arm64-v8a/liboqs.so
///   ├── liboqs-android-armeabi-v7a/liboqs.so
///   ├── liboqs-android-x86_64/liboqs.so
///   └── liboqs-windows-x86_64/oqs.dll

import 'dart:io';
import 'src/common.dart';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  // Parse arguments
  String? artifactsDir;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--artifacts-dir') {
      artifactsDir = args[i + 1];
    }
  }

  if (artifactsDir == null) {
    logError('Missing required --artifacts-dir');
    _printUsage();
    exit(1);
  }

  if (!Directory(artifactsDir).existsSync()) {
    logError('Artifacts directory not found: $artifactsDir');
    exit(1);
  }

  print('');
  print('========================================');
  print('  Combine Build Artifacts');
  print('========================================');
  print('');
  print('Artifacts directory: $artifactsDir');
  print('');

  try {
    final packageDir = getPackageDir();

    // List available artifacts
    logStep('Available artifacts:');
    await _listArtifacts(artifactsDir);

    // Clean old binaries
    logStep('Cleaning old binaries...');
    await removeDir('${packageDir.path}/bin');
    await removeDir('${packageDir.path}/macos/Libraries');
    await removeDir('${packageDir.path}/ios/Frameworks');
    await removeDir('${packageDir.path}/ios/Libraries');
    await removeDir('${packageDir.path}/android/src/main/jniLibs');

    await ensureDir('${packageDir.path}/bin');

    // Process each platform
    await _copyLinux(artifactsDir, packageDir.path);
    await _createMacOSUniversal(artifactsDir, packageDir.path);
    await _createIOSXCFramework(artifactsDir, packageDir.path);
    await _copyAndroid(artifactsDir, packageDir.path);
    await _copyWindows(artifactsDir, packageDir.path);
    await _createVersionFile(packageDir.path);

    print('');
    print('========================================');
    print('  Combine Complete');
    print('========================================');
    print('');

    logInfo('SUCCESS! All artifacts combined.');
  } catch (e) {
    logError(e.toString());
    exit(1);
  }
}

/// List all artifact files
Future<void> _listArtifacts(String artifactsDir) async {
  final dir = Directory(artifactsDir);
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File) {
      final ext = entity.path.split('.').last;
      if (['so', 'dylib', 'a', 'dll'].contains(ext)) {
        final size = await entity.length();
        print('  ${entity.path} (${_formatSize(size)})');
      }
    }
  }
  print('');
}

/// Copy Linux library
Future<void> _copyLinux(String artifactsDir, String packageDir) async {
  final src = '$artifactsDir/liboqs-linux-x86_64/liboqs.so';
  if (File(src).existsSync()) {
    logStep('Copying Linux library...');
    await ensureDir('$packageDir/bin/linux');
    await copyFile(src, '$packageDir/bin/linux/liboqs.so');
    logInfo('Linux library copied');
  }
}

/// Create macOS Universal Binary
Future<void> _createMacOSUniversal(
  String artifactsDir,
  String packageDir,
) async {
  final arm64 = '$artifactsDir/liboqs-macos-arm64/liboqs.dylib';
  final x86_64 = '$artifactsDir/liboqs-macos-x86_64/liboqs.dylib';

  if (!File(arm64).existsSync() || !File(x86_64).existsSync()) {
    logWarn('macOS artifacts not found, skipping');
    return;
  }

  logStep('Creating macOS Universal Binary...');

  final outputDir = '$packageDir/bin/macos';
  await ensureDir(outputDir);

  await runCommandOrFail('lipo', [
    '-create',
    arm64,
    x86_64,
    '-output',
    '$outputDir/liboqs.dylib',
  ]);

  // Fix install name
  await runCommandOrFail('install_name_tool', [
    '-id',
    '@rpath/liboqs.dylib',
    '$outputDir/liboqs.dylib',
  ]);

  // Copy to Flutter plugin directory
  await ensureDir('$packageDir/macos/Libraries');
  await copyFile(
    '$outputDir/liboqs.dylib',
    '$packageDir/macos/Libraries/liboqs.dylib',
  );

  logInfo('macOS Universal Binary created');
  await runCommand('lipo', ['-info', '$outputDir/liboqs.dylib']);
}

/// Process iOS libraries
///
/// All iOS targets use static libraries (.a) which are linked via CocoaPods.
/// This allows using LookupInProcess() in the build hook.
///
/// We create:
/// 1. XCFramework with device + simulator (for CocoaPods)
/// 2. Copy individual libraries to ios/Libraries/ for CI artifacts
Future<void> _createIOSXCFramework(
  String artifactsDir,
  String packageDir,
) async {
  final device = '$artifactsDir/liboqs-ios-device-arm64/liboqs.a';
  final simArm64 = '$artifactsDir/liboqs-ios-simulator-arm64/liboqs.a';
  final simX86_64 = '$artifactsDir/liboqs-ios-simulator-x86_64/liboqs.a';

  logStep('Processing iOS libraries...');

  // Copy libraries to ios/Libraries/
  final librariesDir = '$packageDir/ios/Libraries';

  // Device static library
  if (File(device).existsSync()) {
    await ensureDir('$librariesDir/device-arm64');
    await copyFile(device, '$librariesDir/device-arm64/liboqs.a');
    logInfo('Copied iOS device library');
  } else {
    logWarn('iOS device artifact not found');
  }

  // Simulator arm64 static library
  if (File(simArm64).existsSync()) {
    await ensureDir('$librariesDir/simulator-arm64');
    await copyFile(simArm64, '$librariesDir/simulator-arm64/liboqs.a');
    logInfo('Copied iOS simulator arm64 library');
  } else {
    logWarn('iOS simulator arm64 artifact not found');
  }

  // Simulator x86_64 static library
  if (File(simX86_64).existsSync()) {
    await ensureDir('$librariesDir/simulator-x86_64');
    await copyFile(simX86_64, '$librariesDir/simulator-x86_64/liboqs.a');
    logInfo('Copied iOS simulator x86_64 library');
  } else {
    logWarn('iOS simulator x86_64 artifact not found');
  }

  // Create XCFramework with device + simulator
  if (File(device).existsSync() &&
      File(simArm64).existsSync() &&
      File(simX86_64).existsSync()) {
    logStep('Creating iOS XCFramework...');

    // Create universal simulator library
    final tempDir = getTempBuildDir();
    await ensureDir(tempDir);
    final universalSimLib = '$tempDir/liboqs-simulator-universal.a';

    await runCommandOrFail('lipo', [
      '-create',
      simArm64,
      simX86_64,
      '-output',
      universalSimLib,
    ]);
    logInfo('Created universal simulator library');

    // Create XCFramework
    final frameworksDir = '$packageDir/ios/Frameworks';
    await removeDir('$frameworksDir/liboqs.xcframework');
    await ensureDir(frameworksDir);

    await runCommandOrFail('xcodebuild', [
      '-create-xcframework',
      '-library',
      device,
      '-library',
      universalSimLib,
      '-output',
      '$frameworksDir/liboqs.xcframework',
    ]);
    logInfo('iOS XCFramework created (device + simulator)');

    // Cleanup temp
    await removeDir(tempDir);
  } else {
    logWarn('Not all iOS artifacts found, skipping XCFramework creation');
  }
}

/// Copy Android libraries
Future<void> _copyAndroid(String artifactsDir, String packageDir) async {
  logStep('Copying Android libraries...');

  final abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  var copied = 0;

  for (final abi in abis) {
    final src = '$artifactsDir/liboqs-android-$abi/liboqs.so';
    if (File(src).existsSync()) {
      final dst = '$packageDir/android/src/main/jniLibs/$abi';
      await ensureDir(dst);
      await copyFile(src, '$dst/liboqs.so');
      logInfo('Copied Android $abi');
      copied++;
    }
  }

  if (copied == 0) {
    logWarn('No Android artifacts found');
  }
}

/// Copy Windows library
Future<void> _copyWindows(String artifactsDir, String packageDir) async {
  final src = '$artifactsDir/liboqs-windows-x86_64/oqs.dll';
  if (File(src).existsSync()) {
    logStep('Copying Windows library...');
    await ensureDir('$packageDir/bin/windows');
    await copyFile(src, '$packageDir/bin/windows/oqs.dll');
    logInfo('Windows library copied');
  }
}

/// Create version file
Future<void> _createVersionFile(String packageDir) async {
  logStep('Creating version file...');

  final version = getLiboqsVersion();
  final now = DateTime.now().toUtc().toIso8601String();

  final content = StringBuffer()
    ..writeln('liboqs_version: $version')
    ..writeln('build_date: $now');

  final commit = Platform.environment['GITHUB_SHA'];
  if (commit != null) {
    content.writeln('commit: $commit');
  }

  await File('$packageDir/bin/VERSION').writeAsString(content.toString());
  logInfo('Version file created');
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

void _printUsage() {
  print('''
Combine Build Artifacts

Usage:
  dart run scripts/combine_artifacts.dart --artifacts-dir DIR

This script combines platform-specific build artifacts into final binaries:
  - macOS Universal Binary (arm64 + x86_64)
  - iOS XCFramework (device + simulator)

Options:
  --artifacts-dir DIR   Directory containing downloaded artifacts

Expected artifacts structure:
  artifacts/
  ├── liboqs-linux-x86_64/liboqs.so
  ├── liboqs-macos-arm64/liboqs.dylib
  ├── liboqs-macos-x86_64/liboqs.dylib
  ├── liboqs-ios-device-arm64/liboqs.a    (static, linked via CocoaPods)
  ├── liboqs-ios-simulator-arm64/liboqs.a (static, linked via CocoaPods)
  ├── liboqs-ios-simulator-x86_64/liboqs.a
  ├── liboqs-android-*/liboqs.so
  └── liboqs-windows-x86_64/oqs.dll
''');
}
