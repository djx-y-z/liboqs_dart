/// Build liboqs for iOS
///
/// Requirements:
///   - macOS with Xcode installed
///   - cmake, ninja (or make)
///
/// Output:
///   ios/Frameworks/liboqs.xcframework/ (for xcframework target)
///   ios/Libraries/<target>/ (for individual targets)
///
/// iOS device: static library (.a) - Apple requirement
/// iOS simulator: dynamic library (.dylib) - Flutter native assets requirement

import 'dart:io';
import 'common.dart';

/// iOS build target
enum IOSTarget {
  device, // Static library for device (arm64)
  simulatorArm64, // Dynamic library for simulator (arm64)
  simulatorX86_64, // Dynamic library for simulator (x86_64)
  all, // Build all targets
}

/// Build liboqs for iOS
Future<void> buildIOS({IOSTarget target = IOSTarget.all}) async {
  if (!Platform.isMacOS) {
    throw Exception('iOS build must be run on macOS');
  }

  print('');
  print('========================================');
  print('  liboqs Build: iOS (${target.name})');
  print('========================================');
  print('');

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

  if (target == IOSTarget.all) {
    // Build all targets:
    // - Device: static library (.a)
    // - Simulator: dynamic library (.dylib) for each architecture

    // Device (static)
    final deviceLib = await _buildIOSTarget(
      target: 'device',
      arch: 'arm64',
      sdk: 'iphoneos',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
      sharedLib: false, // Static for device
    );

    // Simulator arm64 (dynamic)
    final simArm64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'arm64',
      sdk: 'iphonesimulator',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
      sharedLib: true, // Dynamic for simulator
    );

    // Simulator x86_64 (dynamic)
    final simX86_64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'x86_64',
      sdk: 'iphonesimulator',
      processor: 'x86_64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
      sharedLib: true, // Dynamic for simulator
    );

    // Copy outputs to proper locations
    final outputDir = '${packageDir.path}/ios/Libraries';

    // Device static library
    final deviceOutputDir = '$outputDir/device-arm64';
    await ensureDir(deviceOutputDir);
    await copyFile(deviceLib, '$deviceOutputDir/liboqs.a');

    // Simulator dynamic libraries (separate, not universal)
    final simArm64OutputDir = '$outputDir/simulator-arm64';
    await ensureDir(simArm64OutputDir);
    await copyFile(simArm64Lib, '$simArm64OutputDir/liboqs.dylib');

    final simX86_64OutputDir = '$outputDir/simulator-x86_64';
    await ensureDir(simX86_64OutputDir);
    await copyFile(simX86_64Lib, '$simX86_64OutputDir/liboqs.dylib');

    // Also create XCFramework for device only (for CocoaPods/SPM compatibility)
    logStep('Creating XCFramework for device...');
    final frameworkDir = '${packageDir.path}/ios/Frameworks';
    await removeDir('$frameworkDir/liboqs.xcframework');
    await ensureDir(frameworkDir);

    await runCommandOrFail('xcodebuild', [
      '-create-xcframework',
      '-library',
      deviceLib,
      '-output',
      '$frameworkDir/liboqs.xcframework',
    ]);

    logInfo('Device XCFramework created at $frameworkDir/liboqs.xcframework');

    // Show info
    logInfo('Build outputs:');
    logInfo('  Device (static):     $deviceOutputDir/liboqs.a');
    logInfo('  Simulator arm64:     $simArm64OutputDir/liboqs.dylib');
    logInfo('  Simulator x86_64:    $simX86_64OutputDir/liboqs.dylib');

    printBuildSummary('iOS all targets', outputDir);
  } else {
    // Build single target
    final (targetName, arch, sdk, processor, isShared) = switch (target) {
      IOSTarget.device => ('device', 'arm64', 'iphoneos', 'aarch64', false),
      IOSTarget.simulatorArm64 => (
        'simulator',
        'arm64',
        'iphonesimulator',
        'aarch64',
        true,
      ),
      IOSTarget.simulatorX86_64 => (
        'simulator',
        'x86_64',
        'iphonesimulator',
        'x86_64',
        true,
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
      sharedLib: isShared,
    );

    // Copy to output
    final outputDir = '${packageDir.path}/ios/Libraries/$targetName-$arch';
    final libName = isShared ? 'liboqs.dylib' : 'liboqs.a';
    await ensureDir(outputDir);
    await copyFile(libPath, '$outputDir/$libName');

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
  required bool sharedLib,
}) async {
  final libType = sharedLib ? 'dynamic' : 'static';
  logPlatform('iOS', 'Building $libType library for $target $arch...');

  // Get SDK path
  final sdkResult = await runCommand('xcrun', [
    '--sdk',
    sdk,
    '--show-sdk-path',
  ], printOutput: false);
  final sdkPath = sdkResult.stdout.toString().trim();
  logInfo('SDK: $sdkPath');

  final buildDir = '$tempDir/build-ios-$target-$arch-$libType';
  await ensureDir(buildDir);

  final cmakeArgs = [
    sourceDir,
    ...getBaseCMakeArgs(),
    '-DBUILD_SHARED_LIBS=${sharedLib ? 'ON' : 'OFF'}',
    '-DOQS_DIST_BUILD=OFF',
    '-DOQS_OPT_TARGET=generic',
    '-DOQS_PERMIT_UNSUPPORTED_ARCHITECTURE=ON',
    '-DCMAKE_SYSTEM_NAME=iOS',
    '-DCMAKE_SYSTEM_PROCESSOR=$processor',
    '-DCMAKE_OSX_ARCHITECTURES=$arch',
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0',
    '-DCMAKE_OSX_SYSROOT=$sdkPath',
    // For dynamic libraries, set install name
    if (sharedLib) '-DCMAKE_INSTALL_NAME_DIR=@rpath',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  final buildArgs = await getBuildArgs();
  await runCommandOrFail(buildTool, buildArgs, workingDirectory: buildDir);

  final libName = sharedLib ? 'liboqs.dylib' : 'liboqs.a';
  return '$buildDir/lib/$libName';
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
