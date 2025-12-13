/// Build liboqs for Windows x86_64
///
/// Requirements:
///   - Windows
///   - cmake, ninja (or MSBuild)
///   - Visual Studio with C++ workload (or Build Tools)
///
/// Output:
///   bin/windows/oqs.dll

import 'dart:io';
import 'common.dart';

/// Build liboqs for Windows
Future<void> buildWindows() async {
  if (!Platform.isWindows) {
    throw Exception('Windows build must be run on Windows');
  }

  printBuildHeader('Windows x86_64');

  // Check dependencies
  logStep('Checking dependencies...');
  await requireCommand('cmake');
  await requireCommand('git');

  // Check for Visual Studio compiler
  final hasVS = await _checkVisualStudio();
  if (!hasVS) {
    logWarn('MSVC compiler (cl.exe) not found in PATH');
    logWarn('Run this script from "Developer PowerShell for VS"');
    logWarn('Or run: vcvars64.bat');
    throw Exception('Visual Studio environment not set up');
  }

  final useNinja = await commandExists('ninja');
  logInfo('Build tool: ${useNinja ? 'ninja' : 'MSBuild'}');

  // Get version
  final version = getLiboqsVersion();
  logInfo('liboqs version: $version');

  // Setup directories
  final packageDir = getPackageDir();
  final tempDir = getTempBuildDir();
  final sourceDir = '$tempDir\\liboqs';
  final buildDir = '$tempDir\\build';
  final outputDir = '${packageDir.path}\\bin\\windows';

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
    '-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON',
    if (useNinja) ...['-G', 'Ninja'],
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  // Build
  logStep('Building...');
  if (useNinja) {
    await runCommandOrFail('ninja', [], workingDirectory: buildDir);
  } else {
    await runCommandOrFail('cmake', [
      '--build',
      '.',
      '--config',
      'Release',
    ], workingDirectory: buildDir);
  }

  // Find and copy DLL
  logStep('Copying library...');
  await ensureDir(outputDir);

  final dllPath = await _findDll(buildDir);
  if (dllPath == null) {
    throw Exception('oqs.dll not found in build directory');
  }

  await copyFile(dllPath, '$outputDir\\oqs.dll');

  // Cleanup
  logStep('Cleaning up...');
  await removeDir(tempDir);

  // Summary
  printBuildSummary('Windows x86_64', outputDir);
  logInfo('SUCCESS! Windows build complete.');
}

/// Check if Visual Studio environment is set up
Future<bool> _checkVisualStudio() async {
  try {
    final result = await Process.run('where', ['cl'], runInShell: true);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Find the built DLL in the build directory
Future<String?> _findDll(String buildDir) async {
  final dir = Directory(buildDir);

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('oqs.dll')) {
      return entity.path;
    }
  }

  return null;
}
