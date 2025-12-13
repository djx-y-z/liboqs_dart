#!/usr/bin/env dart

/// Regenerate Dart FFI bindings for liboqs
///
/// This script downloads liboqs, builds it to generate headers,
/// fixes cyclic includes, and runs ffigen to generate Dart bindings.
///
/// Usage:
///   dart run scripts/regenerate_bindings.dart
///
/// Requirements:
///   - cmake
///   - ninja (optional, falls back to make)
///   - dart sdk with ffigen

import 'dart:io';
import 'src/common.dart';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  print('');
  print('========================================');
  print('  liboqs Dart Bindings Regenerator');
  print('========================================');
  print('');

  try {
    await _checkRequirements();
    final version = getLiboqsVersion();
    logInfo('Target liboqs version: $version');

    await _downloadLiboqs(version);
    await _buildLiboqs();
    await _copyHeaders();
    await _fixCyclicIncludes();
    await _generateBindings();
    final testsPassed = await _runTests();
    await _cleanup();

    print('');
    if (testsPassed) {
      logInfo('SUCCESS! Bindings regenerated for liboqs $version');
    } else {
      logWarn('Bindings generated but tests failed');
      logWarn('Manual review may be needed');
    }

    print('');
    print('Next steps:');
    print('  1. Review changes: git diff lib/src/bindings/');
    print('  2. Run full tests: dart test');
    print('  3. Commit changes if everything works');
    print('');
  } catch (e) {
    logError(e.toString());
    exit(1);
  }
}

final _tempDir = getTempBuildDir();
final _sourceDir = '$_tempDir/liboqs';
final _buildDir = '$_tempDir/build';
late final Directory _packageDir;
late final String _headersDir;

/// Check requirements
Future<void> _checkRequirements() async {
  logStep('Checking requirements...');

  await requireCommand('cmake');
  await requireCommand('dart');

  _packageDir = getPackageDir();
  _headersDir = '${_packageDir.path}/headers/oqs';

  // Check if ffigen is available
  final result = await runCommand(
    'dart',
    ['pub', 'deps'],
    workingDirectory: _packageDir.path,
    printOutput: false,
  );

  if (!result.stdout.toString().contains('ffigen')) {
    logWarn('ffigen not found in dependencies, running dart pub get...');
    await runCommandOrFail('dart', [
      'pub',
      'get',
    ], workingDirectory: _packageDir.path);
  }

  logInfo('All requirements satisfied');
}

/// Download liboqs source
Future<void> _downloadLiboqs(String version) async {
  logStep('Downloading liboqs $version...');

  await removeDir(_tempDir);
  await ensureDir(_tempDir);

  await gitClone(
    url: 'https://github.com/open-quantum-safe/liboqs.git',
    targetDir: _sourceDir,
    branch: version,
  );

  logInfo('Downloaded to $_sourceDir');
}

/// Build liboqs to generate headers
Future<void> _buildLiboqs() async {
  logStep('Building liboqs to generate headers...');

  await ensureDir(_buildDir);

  // Configure with cmake
  final cmakeArgs = [
    _sourceDir,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DOQS_BUILD_ONLY_LIB=ON',
    '-DOQS_USE_OPENSSL=OFF',
    '-DOQS_DIST_BUILD=ON',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: _buildDir);

  // Build (we need to run build for headers to be generated)
  logInfo('Building (this may take a few minutes)...');

  final buildTool = await getBuildCommand();
  final buildArgs = await getBuildArgs();

  // Try to build, but don't fail if it doesn't complete
  try {
    await runCommandOrFail(buildTool, buildArgs, workingDirectory: _buildDir);
  } catch (_) {
    logWarn('Build did not complete fully, but headers may be available');
  }

  // Check if headers were generated
  final includeDir = Directory('$_buildDir/include/oqs');
  if (!includeDir.existsSync()) {
    throw Exception('Headers were not generated in ${includeDir.path}');
  }

  logInfo('Headers generated in ${includeDir.path}');
}

/// Copy headers to package
Future<void> _copyHeaders() async {
  logStep('Copying headers to $_headersDir...');

  await removeDir(_headersDir);
  await ensureDir(_headersDir);

  final sourceHeaders = Directory('$_buildDir/include/oqs');
  var count = 0;

  await for (final file in sourceHeaders.list()) {
    if (file is File && file.path.endsWith('.h')) {
      final name = file.path.split(Platform.pathSeparator).last;
      await file.copy('$_headersDir/$name');
      count++;
    }
  }

  logInfo('Copied $count header files');
}

/// Fix cyclic includes in headers
Future<void> _fixCyclicIncludes() async {
  logStep('Fixing cyclic includes...');

  final headersDir = Directory(_headersDir);
  var fixedCount = 0;

  await for (final file in headersDir.list()) {
    if (file is File && file.path.endsWith('.h')) {
      var content = await file.readAsString();

      if (content.contains('#include <oqs/oqs.h>')) {
        content = content.replaceAll(
          '#include <oqs/oqs.h>',
          '#include <oqs/common.h>',
        );
        await file.writeAsString(content);
        fixedCount++;
      }
    }
  }

  logInfo('Fixed cyclic includes in $fixedCount files');
}

/// Generate Dart bindings using ffigen
Future<void> _generateBindings() async {
  logStep('Generating Dart FFI bindings...');

  final result = await runCommand('dart', [
    'run',
    'ffigen',
  ], workingDirectory: _packageDir.path);

  if (result.exitCode != 0) {
    throw Exception('ffigen failed');
  }

  // Verify bindings were generated
  final bindingsFile = File(
    '${_packageDir.path}/lib/src/bindings/liboqs_bindings.dart',
  );
  if (!bindingsFile.existsSync()) {
    throw Exception('Bindings file was not generated');
  }

  final lineCount = await bindingsFile.readAsLines().then((l) => l.length);
  if (lineCount < 1000) {
    throw Exception(
      'Generated bindings seem too small ($lineCount lines). '
      'Check ffigen output for errors.',
    );
  }

  logInfo('Generated bindings: $lineCount lines');
}

/// Run quick tests to verify bindings
Future<bool> _runTests() async {
  logStep('Running tests to verify bindings...');

  final testFile = File('${_packageDir.path}/test/quick_test.dart');
  if (!testFile.existsSync()) {
    logWarn('Quick test file not found, skipping tests');
    return true;
  }

  final result = await runCommand('dart', [
    'test',
    'test/quick_test.dart',
  ], workingDirectory: _packageDir.path);

  if (result.exitCode == 0) {
    logInfo('Quick test passed!');
    return true;
  } else {
    logWarn('Quick test failed');
    return false;
  }
}

/// Cleanup temporary files
Future<void> _cleanup() async {
  logStep('Cleaning up temporary files...');
  await removeDir(_tempDir);
}

void _printUsage() {
  print('''
Regenerate Dart FFI Bindings for liboqs

Usage:
  dart run scripts/regenerate_bindings.dart

This script:
  1. Reads version from LIBOQS_VERSION file
  2. Downloads liboqs source code
  3. Builds liboqs to generate headers
  4. Fixes cyclic includes in headers
  5. Runs ffigen to generate Dart bindings
  6. Runs quick tests to verify

Requirements:
  - cmake
  - ninja (optional, faster builds)
  - dart sdk with ffigen dependency
''');
}
