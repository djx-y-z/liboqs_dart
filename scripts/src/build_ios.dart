/// Build liboqs for iOS (XCFramework with static libraries)
///
/// Requirements:
///   - macOS with Xcode installed
///   - cmake, ninja (or make)
///
/// Output:
///   ios/Frameworks/liboqs.xcframework/
///
/// iOS apps cannot load arbitrary dylibs, so we build static libraries
/// and package them as XCFramework for both device and simulator.

import 'dart:io';
import 'common.dart';

/// iOS build target
enum IOSTarget {
  device,
  simulatorArm64,
  simulatorX86_64,
  all,
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
    // Build all targets and create XCFramework
    final deviceLib = await _buildIOSTarget(
      target: 'device',
      arch: 'arm64',
      sdk: 'iphoneos',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    final simArm64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'arm64',
      sdk: 'iphonesimulator',
      processor: 'aarch64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    final simX86_64Lib = await _buildIOSTarget(
      target: 'simulator',
      arch: 'x86_64',
      sdk: 'iphonesimulator',
      processor: 'x86_64',
      sourceDir: sourceDir,
      tempDir: tempDir,
      buildTool: buildTool,
    );

    // Create universal simulator library
    logStep('Creating universal simulator library...');
    final simUniversalDir = '$tempDir/ios-simulator-universal';
    await ensureDir(simUniversalDir);

    await runCommandOrFail('lipo', [
      '-create',
      simArm64Lib,
      simX86_64Lib,
      '-output',
      '$simUniversalDir/liboqs.a',
    ]);

    // Create XCFramework
    logStep('Creating XCFramework...');
    final outputDir = '${packageDir.path}/ios/Frameworks';
    await removeDir('$outputDir/liboqs.xcframework');
    await ensureDir(outputDir);

    await runCommandOrFail('xcodebuild', [
      '-create-xcframework',
      '-library',
      deviceLib,
      '-library',
      '$simUniversalDir/liboqs.a',
      '-output',
      '$outputDir/liboqs.xcframework',
    ]);

    logInfo('XCFramework created at $outputDir/liboqs.xcframework');

    // Show info
    await runCommand('find', [
      '$outputDir/liboqs.xcframework',
      '-name',
      '*.a',
      '-exec',
      'file',
      '{}',
      ';',
    ]);

    printBuildSummary('iOS XCFramework', outputDir);
  } else {
    // Build single target
    final (targetName, arch, sdk, processor) = switch (target) {
      IOSTarget.device => ('device', 'arm64', 'iphoneos', 'aarch64'),
      IOSTarget.simulatorArm64 => ('simulator', 'arm64', 'iphonesimulator', 'aarch64'),
      IOSTarget.simulatorX86_64 => ('simulator', 'x86_64', 'iphonesimulator', 'x86_64'),
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
}) async {
  logPlatform('iOS', 'Building for $target $arch...');

  // Get SDK path
  final sdkResult = await runCommand(
    'xcrun',
    ['--sdk', sdk, '--show-sdk-path'],
    printOutput: false,
  );
  final sdkPath = sdkResult.stdout.toString().trim();
  logInfo('SDK: $sdkPath');

  final buildDir = '$tempDir/build-ios-$target-$arch';
  await ensureDir(buildDir);

  final cmakeArgs = [
    sourceDir,
    ...getBaseCMakeArgs(),
    '-DBUILD_SHARED_LIBS=OFF', // Static library for iOS
    '-DOQS_DIST_BUILD=OFF',
    '-DOQS_OPT_TARGET=generic',
    '-DOQS_PERMIT_UNSUPPORTED_ARCHITECTURE=ON',
    '-DCMAKE_SYSTEM_NAME=iOS',
    '-DCMAKE_SYSTEM_PROCESSOR=$processor',
    '-DCMAKE_OSX_ARCHITECTURES=$arch',
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0',
    '-DCMAKE_OSX_SYSROOT=$sdkPath',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  final buildArgs = await getBuildArgs();
  await runCommandOrFail(buildTool, buildArgs, workingDirectory: buildDir);

  return '$buildDir/lib/liboqs.a';
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
