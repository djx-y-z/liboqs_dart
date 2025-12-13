/// Build liboqs for Linux x86_64
///
/// Requirements:
///   - Linux OS
///   - cmake, ninja (or make), gcc/g++
///
/// Output:
///   bin/linux/liboqs.so

import 'dart:io';
import 'common.dart';

/// Build liboqs for Linux
Future<void> buildLinux() async {
  if (!Platform.isLinux) {
    throw Exception('Linux build must be run on Linux');
  }

  printBuildHeader('Linux x86_64');

  // Check dependencies
  logStep('Checking dependencies...');
  await requireCommand('cmake');
  await requireCommand('gcc');
  await requireCommand('g++');

  final buildTool = await getBuildCommand();
  logInfo('Build tool: $buildTool');

  // Get version
  final version = getLiboqsVersion();
  logInfo('liboqs version: $version');

  // Setup directories
  final packageDir = getPackageDir();
  final tempDir = getTempBuildDir();
  final sourceDir = '$tempDir/liboqs';
  final buildDir = '$tempDir/build-linux';
  final outputDir = '${packageDir.path}/bin/linux';

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

  // Configure with CMake
  logStep('Configuring with CMake...');
  await ensureDir(buildDir);

  final cmakeArgs = [
    sourceDir,
    ...getBaseCMakeArgs(),
    '-DBUILD_SHARED_LIBS=ON',
    '-DOQS_DIST_BUILD=ON',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  // Build
  logStep('Building...');
  final buildArgs = await getBuildArgs();
  await runCommandOrFail(buildTool, buildArgs, workingDirectory: buildDir);

  // Copy output
  logStep('Copying library...');
  await ensureDir(outputDir);
  await copyFile('$buildDir/lib/liboqs.so', '$outputDir/liboqs.so');

  // Cleanup
  logStep('Cleaning up...');
  await removeDir(tempDir);

  // Summary
  printBuildSummary('Linux x86_64', outputDir);
  logInfo('SUCCESS! Linux build complete.');
}
