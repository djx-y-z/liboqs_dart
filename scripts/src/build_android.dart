/// Build liboqs for Android (all ABIs)
///
/// Requirements:
///   - Linux or macOS
///   - cmake, ninja (or make)
///   - Android NDK (set ANDROID_NDK_HOME or auto-detect)
///
/// Output:
///   android/src/main/jniLibs/arm64-v8a/liboqs.so
///   android/src/main/jniLibs/armeabi-v7a/liboqs.so
///   android/src/main/jniLibs/x86_64/liboqs.so

import 'dart:io';
import 'common.dart';

/// Android ABI to build for
enum AndroidAbi {
  arm64V8a('arm64-v8a'),
  armeabiV7a('armeabi-v7a'),
  x86_64('x86_64'),
  all('all');

  final String value;
  const AndroidAbi(this.value);
}

/// Build liboqs for Android
Future<void> buildAndroid({AndroidAbi abi = AndroidAbi.all}) async {
  if (!Platform.isLinux && !Platform.isMacOS) {
    throw Exception('Android build must be run on Linux or macOS');
  }

  printBuildHeader('Android (${abi.value})');

  // Check dependencies
  logStep('Checking dependencies...');
  await requireCommand('cmake');

  final buildTool = await getBuildCommand();
  logInfo('Build tool: $buildTool');

  // Find NDK
  final ndkPath = await _findNDK();
  logInfo('Android NDK: $ndkPath');

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

  // Determine which ABIs to build
  final abis = abi == AndroidAbi.all
      ? [AndroidAbi.arm64V8a, AndroidAbi.armeabiV7a, AndroidAbi.x86_64]
      : [abi];

  // Build each ABI
  for (final targetAbi in abis) {
    await _buildAbi(
      abi: targetAbi.value,
      ndkPath: ndkPath,
      sourceDir: sourceDir,
      tempDir: tempDir,
      packageDir: packageDir.path,
      buildTool: buildTool,
    );
  }

  // Cleanup
  logStep('Cleaning up...');
  await removeDir(tempDir);

  // Summary
  final outputDir = '${packageDir.path}/android/src/main/jniLibs';
  printBuildSummary('Android', outputDir);
  logInfo('SUCCESS! Android build complete.');
}

/// Find Android NDK path
Future<String> _findNDK() async {
  logStep('Looking for Android NDK...');

  // Check ANDROID_NDK_HOME first
  final ndkHome = Platform.environment['ANDROID_NDK_HOME'];
  if (ndkHome != null && Directory(ndkHome).existsSync()) {
    return ndkHome;
  }

  // Try common locations
  final possiblePaths = [
    Platform.environment['ANDROID_SDK_ROOT'],
    Platform.environment['ANDROID_HOME'],
    if (Platform.isMacOS) '${Platform.environment['HOME']}/Library/Android/sdk',
    if (Platform.isLinux) '${Platform.environment['HOME']}/Android/Sdk',
    '/usr/local/share/android-sdk',
  ];

  for (final basePath in possiblePaths) {
    if (basePath == null) continue;

    final ndkDir = Directory('$basePath/ndk');
    if (ndkDir.existsSync()) {
      // Find newest version
      final versions =
          ndkDir
              .listSync()
              .whereType<Directory>()
              .map((d) => d.path.split('/').last)
              .toList()
            ..sort();

      if (versions.isNotEmpty) {
        return '${ndkDir.path}/${versions.last}';
      }
    }
  }

  throw Exception('''
Android NDK not found!

Set ANDROID_NDK_HOME environment variable or install NDK via Android Studio:
  1. Open Android Studio -> SDK Manager -> SDK Tools
  2. Check 'NDK (Side by side)' and install

Or set manually:
  export ANDROID_NDK_HOME=/path/to/ndk/26.3.11579264
''');
}

/// Build for a specific ABI
Future<void> _buildAbi({
  required String abi,
  required String ndkPath,
  required String sourceDir,
  required String tempDir,
  required String packageDir,
  required String buildTool,
}) async {
  logPlatform('Android', 'Building for $abi...');

  final buildDir = '$tempDir/build-android-$abi';
  await ensureDir(buildDir);

  final toolchainFile = '$ndkPath/build/cmake/android.toolchain.cmake';
  if (!File(toolchainFile).existsSync()) {
    throw Exception('NDK toolchain not found: $toolchainFile');
  }

  final cmakeArgs = [
    sourceDir,
    ...getBaseCMakeArgs(),
    '-DBUILD_SHARED_LIBS=ON',
    '-DOQS_DIST_BUILD=OFF',
    '-DOQS_OPT_TARGET=generic',
    '-DCMAKE_TOOLCHAIN_FILE=$toolchainFile',
    '-DANDROID_ABI=$abi',
    '-DANDROID_PLATFORM=android-21',
    '-DANDROID_STL=c++_shared',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  final buildArgs = await getBuildArgs();
  await runCommandOrFail(buildTool, buildArgs, workingDirectory: buildDir);

  // Copy output
  final outputDir = '$packageDir/android/src/main/jniLibs/$abi';
  await ensureDir(outputDir);
  await copyFile('$buildDir/lib/liboqs.so', '$outputDir/liboqs.so');

  logInfo('Built $abi');
}

/// Parse ABI from command line argument
AndroidAbi parseAbi(String? arg) {
  switch (arg?.toLowerCase()) {
    case 'arm64-v8a':
    case 'arm64':
      return AndroidAbi.arm64V8a;
    case 'armeabi-v7a':
    case 'arm32':
    case 'armv7':
      return AndroidAbi.armeabiV7a;
    case 'x86_64':
    case 'x64':
      return AndroidAbi.x86_64;
    case 'all':
    case null:
      return AndroidAbi.all;
    default:
      throw Exception('Unknown Android ABI: $arg');
  }
}
