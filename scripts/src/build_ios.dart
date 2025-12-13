/// Build liboqs for iOS
///
/// Requirements:
///   - macOS with Xcode installed
///   - cmake, ninja (or make)
///
/// Output:
///   ios/Libraries/<target>-<arch>/liboqs.dylib
///
/// All iOS targets use dynamic libraries (.dylib) which are bundled via
/// Flutter's native assets system (DynamicLoadingBundled). Flutter automatically
/// converts .dylib to Framework format required by App Store.

import 'dart:io';
import 'common.dart';

/// iOS build target
enum IOSTarget {
  device, // Dynamic library for device (arm64)
  simulatorArm64, // Dynamic library for simulator (arm64)
  simulatorX86_64, // Dynamic library for simulator (x86_64)
  all, // Build all targets
}

/// Build liboqs for iOS
Future<void> buildIOS({IOSTarget target = IOSTarget.all}) async {
  if (!Platform.isMacOS) {
    throw Exception('iOS build must be run on macOS');
  }

  printBuildHeader('iOS (${target.name})');

  // Check dependencies
  logStep('Checking dependencies...');
  await requireCommand('cmake');
  await requireCommand('xcodebuild');
  await requireCommand('xcrun');

  final buildTool = await getBuildCommand();
  logInfo('Build tool: $buildTool');

  // Get version
  final version = getLiboqsVersion();
  logInfo('liboqs version: $version');

  // Setup directories
  final packageDir = getPackageDir();
  final tempDir = getTempBuildDir();
  final sourceDir = '$tempDir/liboqs';

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

  // Output directory for all iOS libraries
  final outputBaseDir = '${packageDir.path}/ios/Libraries';

  if (target == IOSTarget.all) {
    // Build all targets as dynamic libraries (.dylib)
    // Flutter will convert these to Frameworks automatically

    // Device arm64
    final deviceLib = await _buildIOSTarget(
      target: 'device',
      arch: 'arm64',
      sdk: 'iphoneos',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    // Simulator arm64
    final simArm64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'arm64',
      sdk: 'iphonesimulator',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    // Simulator x86_64
    final simX86_64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'x86_64',
      sdk: 'iphonesimulator',
      processor: 'x86_64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    // Copy outputs to proper locations
    final deviceOutputDir = '$outputBaseDir/device-arm64';
    await ensureDir(deviceOutputDir);
    await copyFile(deviceLib, '$deviceOutputDir/liboqs.dylib');

    final simArm64OutputDir = '$outputBaseDir/simulator-arm64';
    await ensureDir(simArm64OutputDir);
    await copyFile(simArm64Lib, '$simArm64OutputDir/liboqs.dylib');

    final simX86_64OutputDir = '$outputBaseDir/simulator-x86_64';
    await ensureDir(simX86_64OutputDir);
    await copyFile(simX86_64Lib, '$simX86_64OutputDir/liboqs.dylib');

    // Show info
    logInfo('Build outputs:');
    logInfo('  Device arm64:     $deviceOutputDir/liboqs.dylib');
    logInfo('  Simulator arm64:  $simArm64OutputDir/liboqs.dylib');
    logInfo('  Simulator x86_64: $simX86_64OutputDir/liboqs.dylib');

    printBuildSummary('iOS all targets', outputBaseDir);
  } else {
    // Build single target
    final (targetName, arch, sdk, processor) = switch (target) {
      IOSTarget.device => ('device', 'arm64', 'iphoneos', 'aarch64'),
      IOSTarget.simulatorArm64 => (
        'simulator',
        'arm64',
        'iphonesimulator',
        'aarch64',
      ),
      IOSTarget.simulatorX86_64 => (
        'simulator',
        'x86_64',
        'iphonesimulator',
        'x86_64',
      ),
      IOSTarget.all => throw Exception('Unreachable'),
    };

    final libPath = await _buildIOSTarget(
      target: targetName,
      arch: arch,
      sdk: sdk,
      processor: processor,
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    // Copy to output
    final outputDir = '$outputBaseDir/$targetName-$arch';
    await ensureDir(outputDir);
    await copyFile(libPath, '$outputDir/liboqs.dylib');

    printBuildSummary('iOS $targetName $arch', outputDir);
  }

  // Cleanup
  logStep('Cleaning up...');
  await removeDir(tempDir);

  logInfo('SUCCESS! iOS build complete.');
}

/// Build for a specific iOS target
Future<String> _buildIOSTarget({
  required String target,
  required String arch,
  required String sdk,
  required String processor,
  required String sourceDir,
  required String tempDir,
  required String buildTool,
}) async {
  logPlatform('iOS', 'Building dynamic library for $target $arch...');

  // Get SDK path
  final sdkResult = await runCommand('xcrun', [
    '--sdk',
    sdk,
    '--show-sdk-path',
  ], printOutput: false);
  final sdkPath = sdkResult.stdout.toString().trim();
  logInfo('SDK: $sdkPath');

  final buildDir = '$tempDir/build-ios-$target-$arch';
  await ensureDir(buildDir);

  final cmakeArgs = [
    sourceDir,
    ...getBaseCMakeArgs(),
    '-DBUILD_SHARED_LIBS=ON',
    '-DOQS_DIST_BUILD=OFF',
    '-DOQS_OPT_TARGET=generic',
    '-DOQS_PERMIT_UNSUPPORTED_ARCHITECTURE=ON',
    '-DCMAKE_SYSTEM_NAME=iOS',
    '-DCMAKE_SYSTEM_PROCESSOR=$processor',
    '-DCMAKE_OSX_ARCHITECTURES=$arch',
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0',
    '-DCMAKE_OSX_SYSROOT=$sdkPath',
    // Set install name for dynamic library loading
    '-DCMAKE_INSTALL_NAME_DIR=@rpath',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  final buildArgs = await getBuildArgs();
  await runCommandOrFail(buildTool, buildArgs, workingDirectory: buildDir);

  return '$buildDir/lib/liboqs.dylib';
}

/// Parse target from command line argument
IOSTarget parseTarget(String? arg) {
  switch (arg?.toLowerCase()) {
    case 'device':
      return IOSTarget.device;
    case 'simulator-arm64':
    case 'sim-arm64':
      return IOSTarget.simulatorArm64;
    case 'simulator-x86_64':
    case 'sim-x86_64':
    case 'simulator-x64':
    case 'sim-x64':
      return IOSTarget.simulatorX86_64;
    case 'all':
    case null:
      return IOSTarget.all;
    default:
      throw Exception('Unknown iOS target: $arg');
  }
}
