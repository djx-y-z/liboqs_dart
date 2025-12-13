/// Build liboqs for macOS (Universal Binary)
///
/// Requirements:
///   - macOS
///   - cmake, ninja (or make), Xcode Command Line Tools
///
/// Output:
///   bin/macos/liboqs.dylib (Universal: arm64 + x86_64)
///   macos/Libraries/liboqs.dylib (copy for Flutter plugin)

import 'dart:io';
import 'common.dart';

/// Architecture to build for
enum MacOSArch { arm64, x86_64, universal }

/// Build liboqs for macOS
Future<void> buildMacOS({MacOSArch arch = MacOSArch.universal}) async {
  if (!Platform.isMacOS) {
    throw Exception('macOS build must be run on macOS');
  }

  printBuildHeader('macOS (${arch.name})');

  // Check dependencies
  logStep('Checking dependencies...');
  await requireCommand('cmake');
  await requireCommand('clang');

  final buildTool = await getBuildCommand();
  logInfo('Build tool: $buildTool');

  // Get version
  final version = getLiboqsVersion();
  logInfo('liboqs version: $version');

  // Setup directories
  final packageDir = getPackageDir();
  final tempDir = getTempBuildDir();
  final sourceDir = '$tempDir/liboqs';
  final outputDir = '${packageDir.path}/bin/macos';
  final flutterDir = '${packageDir.path}/macos/Libraries';

  // Clean and create temp directory
  logStep('Preparing build directory...');
  await removeDir(tempDir);
  await ensureDir(tempDir);

  // Clone liboqs
  logStep('Downloading liboqs $version...');
  await gitClone(
    url: 'https://github.com/open-quantum-safe/liboqs.git',
    targetDir: sourceDir,
    branch: version,
  );

  // Build based on architecture
  await ensureDir(outputDir);

  if (arch == MacOSArch.universal) {
    // Build both architectures and combine
    final arm64Lib = await _buildArch(
      arch: 'arm64',
      deploymentTarget: '11.0',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    final x86_64Lib = await _buildArch(
      arch: 'x86_64',
      deploymentTarget: '10.15',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    // Create Universal Binary with lipo
    logStep('Creating Universal Binary...');
    await runCommandOrFail('lipo', [
      '-create',
      arm64Lib,
      x86_64Lib,
      '-output',
      '$outputDir/liboqs.dylib',
    ]);

    logInfo('Universal Binary architectures:');
    await runCommand('lipo', ['-info', '$outputDir/liboqs.dylib']);
  } else {
    // Build single architecture
    final archName = arch == MacOSArch.arm64 ? 'arm64' : 'x86_64';
    final deploymentTarget = arch == MacOSArch.arm64 ? '11.0' : '10.15';

    final libPath = await _buildArch(
      arch: archName,
      deploymentTarget: deploymentTarget,
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    await copyFile(libPath, '$outputDir/liboqs.dylib');
  }

  // Fix install name
  logStep('Fixing install name...');
  await runCommandOrFail('install_name_tool', [
    '-id',
    '@rpath/liboqs.dylib',
    '$outputDir/liboqs.dylib',
  ]);

  // Copy to Flutter plugin directory
  logStep('Copying to Flutter plugin directory...');
  await ensureDir(flutterDir);
  await copyFile('$outputDir/liboqs.dylib', '$flutterDir/liboqs.dylib');

  // Cleanup
  logStep('Cleaning up...');
  await removeDir(tempDir);

  // Summary
  printBuildSummary('macOS ${arch.name}', outputDir);
  logInfo('SUCCESS! macOS build complete.');
}

/// Build for a specific architecture
Future<String> _buildArch({
  required String arch,
  required String deploymentTarget,
  required String sourceDir,
  required String tempDir,
  required String buildTool,
}) async {
  logPlatform(
    'macOS',
    'Building for $arch (deployment target: $deploymentTarget)...',
  );

  final buildDir = '$tempDir/build-macos-$arch';
  await ensureDir(buildDir);

  final cmakeArgs = [
    sourceDir,
    ...getBaseCMakeArgs(),
    '-DBUILD_SHARED_LIBS=ON',
    '-DOQS_DIST_BUILD=ON',
    '-DCMAKE_OSX_ARCHITECTURES=$arch',
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=$deploymentTarget',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  final buildArgs = await getBuildArgs();
  await runCommandOrFail(buildTool, buildArgs, workingDirectory: buildDir);

  return '$buildDir/lib/liboqs.dylib';
}

/// Parse architecture from command line argument
MacOSArch parseArch(String? arg) {
  switch (arg?.toLowerCase()) {
    case 'arm64':
      return MacOSArch.arm64;
    case 'x86_64':
    case 'x64':
    case 'intel':
      return MacOSArch.x86_64;
    case 'universal':
    case null:
      return MacOSArch.universal;
    default:
      throw Exception('Unknown architecture: $arg');
  }
}
