/// Common utilities for build scripts
///
/// This file provides cross-platform utilities for building liboqs
/// native libraries on Linux, macOS, iOS, Android, and Windows.

import 'dart:io';

// ============================================
// ANSI Colors for terminal output
// ============================================

class Colors {
  static const reset = '\x1B[0m';
  static const red = '\x1B[31m';
  static const green = '\x1B[32m';
  static const yellow = '\x1B[33m';
  static const blue = '\x1B[34m';
  static const cyan = '\x1B[36m';

  static bool get supportsAnsi {
    return stdout.supportsAnsiEscapes;
  }

  static String colorize(String text, String color) {
    if (!supportsAnsi) return text;
    return '$color$text$reset';
  }
}

// ============================================
// Logging utilities
// ============================================

void logInfo(String message) {
  print(Colors.colorize('[INFO]', Colors.green) + ' $message');
}

void logWarn(String message) {
  print(Colors.colorize('[WARN]', Colors.yellow) + ' $message');
}

/// Alias for logWarn (consistent naming with other scripts)
void logWarning(String message) => logWarn(message);

void logError(String message) {
  print(Colors.colorize('[ERROR]', Colors.red) + ' $message');
}

void logStep(String message) {
  print(Colors.colorize('[STEP]', Colors.blue) + ' $message');
}

void logSuccess(String message) {
  print(Colors.colorize('[OK]', Colors.green) + ' $message');
}

void logPlatform(String platform, String message) {
  print(Colors.colorize('[$platform]', Colors.cyan) + ' $message');
}

/// Print a build header for a platform
void printBuildHeader(String platform) {
  print('');
  print('========================================');
  print('  liboqs Build: $platform');
  print('========================================');
  print('');
}

// ============================================
// Path utilities
// ============================================

/// Get the package root directory (where pubspec.yaml is located)
Directory getPackageDir() {
  // scripts/src/common.dart -> scripts/src -> scripts -> package root
  var dir = File(Platform.script.toFilePath()).parent.parent.parent;

  // Verify we found the right directory
  if (!File('${dir.path}/pubspec.yaml').existsSync()) {
    // Try resolving from current directory
    dir = Directory.current;
    while (!File('${dir.path}/pubspec.yaml').existsSync()) {
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw Exception('Could not find package root (pubspec.yaml)');
      }
      dir = parent;
    }
  }

  return dir;
}

/// Get the native liboqs version from pubspec.yaml (liboqs.native_version)
String getLiboqsVersion() {
  final packageDir = getPackageDir();
  final pubspecFile = File('${packageDir.path}/pubspec.yaml');

  if (!pubspecFile.existsSync()) {
    throw Exception('pubspec.yaml not found');
  }

  final content = pubspecFile.readAsStringSync();

  // Extract the liboqs: block (until next top-level key or EOF)
  final blockMatch = RegExp(
    r'^liboqs:\s*$([\s\S]*?)(?=^\w|\z)',
    multiLine: true,
  ).firstMatch(content);

  if (blockMatch == null) {
    throw Exception('liboqs: block not found in pubspec.yaml');
  }

  final block = blockMatch.group(1) ?? '';

  // Extract native_version from the block (supports quoted and unquoted values)
  final versionMatch = RegExp(
    r'native_version:\s*"?([^"\s\n]+)"?',
  ).firstMatch(block);

  if (versionMatch == null) {
    throw Exception('native_version not found in liboqs block');
  }

  return versionMatch.group(1)!.trim();
}

/// Get the native build number from pubspec.yaml (liboqs.native_build)
String getNativeBuild() {
  final packageDir = getPackageDir();
  final pubspecFile = File('${packageDir.path}/pubspec.yaml');

  if (!pubspecFile.existsSync()) {
    return '1';
  }

  final content = pubspecFile.readAsStringSync();

  // Extract the liboqs: block
  final blockMatch = RegExp(
    r'^liboqs:\s*$([\s\S]*?)(?=^\w|\z)',
    multiLine: true,
  ).firstMatch(content);

  if (blockMatch == null) {
    return '1';
  }

  final block = blockMatch.group(1) ?? '';

  // Extract native_build from the block
  final buildMatch = RegExp(r'native_build:\s*(\d+)').firstMatch(block);

  return buildMatch?.group(1)?.trim() ?? '1';
}

/// Get full version string (liboqs version + native build)
String getFullVersion() {
  return '${getLiboqsVersion()}-${getNativeBuild()}';
}

/// Get the Dart package version from pubspec.yaml (top-level `version:`)
String getPackageVersion() {
  final packageDir = getPackageDir();
  final pubspecFile = File('${packageDir.path}/pubspec.yaml');

  if (!pubspecFile.existsSync()) {
    throw Exception('pubspec.yaml not found');
  }

  final content = pubspecFile.readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(content);

  if (match == null) {
    throw Exception('Top-level version: not found in pubspec.yaml');
  }

  return match.group(1)!.trim();
}

// ============================================
// Process execution utilities
// ============================================

/// Run a command and return the result
Future<ProcessResult> runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool printOutput = true,
}) async {
  if (printOutput) {
    logInfo('Running: $executable ${arguments.join(' ')}');
  }

  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: Platform.isWindows,
  );

  if (printOutput && result.stdout.toString().isNotEmpty) {
    stdout.write(result.stdout);
  }

  if (result.stderr.toString().isNotEmpty) {
    stderr.write(result.stderr);
  }

  return result;
}

/// Run a command and throw if it fails
Future<void> runCommandOrFail(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool printOutput = true,
}) async {
  final result = await runCommand(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    printOutput: printOutput,
  );

  if (result.exitCode != 0) {
    throw Exception(
      'Command failed with exit code ${result.exitCode}: '
      '$executable ${arguments.join(' ')}',
    );
  }
}

/// Check if a command exists
Future<bool> commandExists(String command) async {
  try {
    final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
      command,
    ], runInShell: true);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Require a command to exist, or throw
Future<void> requireCommand(String command) async {
  if (!await commandExists(command)) {
    throw Exception('Required command not found: $command');
  }
}

/// Check if FVM is available
Future<bool> fvmExists() async {
  return await commandExists('fvm');
}

/// Run a Dart command using FVM if available, otherwise use dart directly
Future<ProcessResult> runDart(
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool printOutput = true,
}) async {
  if (await fvmExists()) {
    return runCommand(
      'fvm',
      ['dart', ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
      printOutput: printOutput,
    );
  }
  return runCommand(
    'dart',
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    printOutput: printOutput,
  );
}

/// Run a Dart command and throw if it fails
Future<void> runDartOrFail(
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool printOutput = true,
}) async {
  final result = await runDart(
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    printOutput: printOutput,
  );

  if (result.exitCode != 0) {
    throw Exception(
      'Dart command failed with exit code ${result.exitCode}: '
      'dart ${arguments.join(' ')}',
    );
  }
}

// ============================================
// Git utilities
// ============================================

/// Clone a git repository
Future<void> gitClone({
  required String url,
  required String targetDir,
  String? branch,
  int depth = 1,
}) async {
  final args = ['clone', '--depth', '$depth'];

  if (branch != null) {
    args.addAll(['--branch', branch]);
  }

  args.addAll([url, targetDir]);

  await runCommandOrFail('git', args);
}

// ============================================
// File system utilities
// ============================================

/// Create directory if it doesn't exist
Future<void> ensureDir(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
}

/// Remove directory if it exists
Future<void> removeDir(String path) async {
  final dir = Directory(path);
  if (dir.existsSync()) {
    await dir.delete(recursive: true);
  }
}

/// Copy file to destination
Future<void> copyFile(String source, String destination) async {
  await ensureDir(Directory(destination).parent.path);
  await File(source).copy(destination);
}

/// Get temporary directory for builds
String getTempBuildDir() {
  if (Platform.isWindows) {
    return 'C:\\liboqs-build';
  }
  return '/tmp/liboqs-build';
}

// ============================================
// Platform detection
// ============================================

enum BuildPlatform { linux, macos, ios, android, windows }

/// Get available build platforms for current OS
List<BuildPlatform> getAvailablePlatforms() {
  if (Platform.isMacOS) {
    return [BuildPlatform.macos, BuildPlatform.ios, BuildPlatform.android];
  } else if (Platform.isLinux) {
    return [BuildPlatform.linux, BuildPlatform.android];
  } else if (Platform.isWindows) {
    return [BuildPlatform.windows];
  }
  return [];
}

/// Check if we can build for a specific platform
bool canBuildFor(BuildPlatform platform) {
  return getAvailablePlatforms().contains(platform);
}

// ============================================
// CMake utilities
// ============================================

/// Common CMake arguments for liboqs
List<String> getBaseCMakeArgs() {
  return [
    '-DOQS_BUILD_ONLY_LIB=ON',
    '-DOQS_USE_OPENSSL=OFF',
    '-DCMAKE_BUILD_TYPE=Release',
  ];
}

/// Check if Ninja is available, return generator args
Future<List<String>> getCMakeGeneratorArgs() async {
  if (await commandExists('ninja')) {
    return ['-G', 'Ninja'];
  }
  return [];
}

/// Get the build command (ninja or make)
Future<String> getBuildCommand() async {
  if (await commandExists('ninja')) {
    return 'ninja';
  }
  return Platform.isWindows ? 'cmake' : 'make';
}

/// Get build command arguments
Future<List<String>> getBuildArgs() async {
  if (await commandExists('ninja')) {
    return [];
  }
  if (Platform.isWindows) {
    return ['--build', '.', '--config', 'Release'];
  }
  // make with parallel jobs
  final cpuCount = Platform.numberOfProcessors;
  return ['-j$cpuCount'];
}

// ============================================
// Build summary
// ============================================

void printBuildSummary(String platform, String outputDir) {
  print('');
  print('========================================');
  print('  Build Complete: $platform');
  print('========================================');
  print('');
  print('Output directory: $outputDir');
  print('Files:');

  final dir = Directory(outputDir);
  if (dir.existsSync()) {
    for (final file in dir.listSync(recursive: true)) {
      if (file is File) {
        final size = file.lengthSync();
        final sizeStr = _formatSize(size);
        print('  ${file.path} ($sizeStr)');
      }
    }
  }
  print('');
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
