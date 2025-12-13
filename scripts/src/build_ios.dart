/// Build liboqs for iOS
///
/// Requirements:
///   - macOS with Xcode installed
///   - cmake, ninja (or make)
///
/// Output:
///   ios/Frameworks/liboqs.xcframework/ (contains static libraries for all architectures)
///
/// All iOS targets use static libraries (.a) which are linked via CocoaPods.
/// This allows using LookupInProcess() in the build hook, which is compatible
/// with Flutter's native assets system for both device and simulator.

import 'dart:io';
import 'common.dart';

/// iOS build target
enum IOSTarget {
  device, // Static library for device (arm64)
  simulatorArm64, // Static library for simulator (arm64)
  simulatorX86_64, // Static library for simulator (x86_64)
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
    // Build all targets as static libraries (.a)
    // Static libraries are linked via CocoaPods xcframework

    // Device arm64 (static)
    final deviceLib = await _buildIOSTarget(
      target: 'device',
      arch: 'arm64',
      sdk: 'iphoneos',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
      sharedLib: false, // Static
    );

    // Simulator arm64 (static)
    final simArm64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'arm64',
      sdk: 'iphonesimulator',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
      sharedLib: false, // Static
    );

    // Simulator x86_64 (static)
    final simX86_64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'x86_64',
      sdk: 'iphonesimulator',
      processor: 'x86_64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
      sharedLib: false, // Static
    );

    // Copy outputs to proper locations
    final outputDir = '${packageDir.path}/ios/Libraries';

    // Device static library
    final deviceOutputDir = '$outputDir/device-arm64';
    await ensureDir(deviceOutputDir);
    await copyFile(deviceLib, '$deviceOutputDir/liboqs.a');

    // Simulator static libraries (separate for CI artifacts)
    final simArm64OutputDir = '$outputDir/simulator-arm64';
    await ensureDir(simArm64OutputDir);
    await copyFile(simArm64Lib, '$simArm64OutputDir/liboqs.a');

    final simX86_64OutputDir = '$outputDir/simulator-x86_64';
    await ensureDir(simX86_64OutputDir);
    await copyFile(simX86_64Lib, '$simX86_64OutputDir/liboqs.a');

    // Create universal simulator library for xcframework
    logStep('Creating universal simulator library...');
    final universalSimLib = '$tempDir/liboqs-simulator-universal.a';
    await runCommandOrFail('lipo', [
      '-create',
      simArm64Lib,
      simX86_64Lib,
      '-output',
      universalSimLib,
    ]);

    // Create XCFramework with device + simulator (for CocoaPods)
    logStep('Creating XCFramework...');
    final frameworkDir = '${packageDir.path}/ios/Frameworks';
    await removeDir('$frameworkDir/liboqs.xcframework');
    await ensureDir(frameworkDir);

    await runCommandOrFail('xcodebuild', [
      '-create-xcframework',
      '-library',
      deviceLib,
      '-library',
      universalSimLib,
      '-output',
      '$frameworkDir/liboqs.xcframework',
    ]);

    logInfo('XCFramework created at $frameworkDir/liboqs.xcframework');

    // Show info
    logInfo('Build outputs:');
    logInfo('  Device (static):        $deviceOutputDir/liboqs.a');
    logInfo('  Simulator arm64 (static): $simArm64OutputDir/liboqs.a');
    logInfo('  Simulator x86_64 (static): $simX86_64OutputDir/liboqs.a');
    logInfo('  XCFramework:            $frameworkDir/liboqs.xcframework');

    printBuildSummary('iOS all targets', outputDir);
  } else {
    // Build single target (all static)
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
      sharedLib: false, // Always static
    );

    // Copy to output
    final outputDir = '${packageDir.path}/ios/Libraries/$targetName-$arch';
    await ensureDir(outputDir);
    await copyFile(libPath, '$outputDir/liboqs.a');

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
