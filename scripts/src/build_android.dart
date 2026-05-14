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

  // Android 15+ devices may use 16 KB memory pages, requiring shared
  // libraries to have LOAD segments aligned to 16 KB. NDK r28+ does this by
  // default; r26/r27 default to 4 KB. We pass the linker flags explicitly so
  // the resulting .so works regardless of which NDK builds it.
  // https://developer.android.com/guide/practices/page-sizes
  const pageAlignFlags =
      '-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384';

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
    '-DCMAKE_SHARED_LINKER_FLAGS=$pageAlignFlags',
    ...await getCMakeGeneratorArgs(),
  ];

  await runCommandOrFail('cmake', cmakeArgs, workingDirectory: buildDir);

  final buildArgs = await getBuildArgs();
  await runCommandOrFail(buildTool, buildArgs, workingDirectory: buildDir);

  // Copy output
  final outputDir = '$packageDir/android/src/main/jniLibs/$abi';
  await ensureDir(outputDir);
  final outputLib = '$outputDir/liboqs.so';
  await copyFile('$buildDir/lib/liboqs.so', outputLib);

  // 64-bit ABIs ship to potentially-16KB-page devices, so verify the
  // resulting LOAD segments are aligned to at least 16 KB. armeabi-v7a is
  // 32-bit only — those devices always use 4 KB pages, so the check is
  // skipped there (the flag itself is harmless on 32-bit).
  if (abi == 'arm64-v8a' || abi == 'x86_64') {
    await _verifyPageAlignment(outputLib, ndkPath);
  }

  logInfo('Built $abi');
}

/// Verifies that all LOAD segments of [soPath] are aligned to at least 16 KB
/// (0x4000), so the library can be loaded on Android 15+ 16 KB-page devices.
///
/// Tries `llvm-readelf` from the NDK (present in NDK r27+) first, then any
/// `llvm-readelf`/`readelf` on `PATH` (binutils ships on most Linux CI
/// runners). If no tool is found the check is skipped with a warning rather
/// than failing the build — the linker flags above guarantee correctness;
/// the verification is a regression catcher, not a hard requirement.
Future<void> _verifyPageAlignment(String soPath, String ndkPath) async {
  logStep('Verifying 16 KB page alignment...');

  final readelf = await _findReadelf(ndkPath);
  if (readelf == null) {
    logInfo(
      'Skipping alignment check: no llvm-readelf/readelf available '
      '(NDK r26 omits llvm-readelf; install binutils or upgrade to NDK r27+).',
    );
    return;
  }

  final result = await Process.run(readelf, ['-lW', soPath]);
  if (result.exitCode != 0) {
    throw Exception('$readelf failed for $soPath: ${result.stderr}');
  }

  // Parse LOAD lines. Format (last column is alignment as hex):
  //   LOAD 0x000000 0x00000000 0x00000000 0x12345 0x12345 R E 0x4000
  final loadLines = (result.stdout as String)
      .split('\n')
      .where((l) => l.trimLeft().startsWith('LOAD'))
      .toList();

  if (loadLines.isEmpty) {
    throw Exception('No LOAD segments found in $soPath');
  }

  for (final line in loadLines) {
    final parts = line.trim().split(RegExp(r'\s+'));
    final alignStr = parts.last;
    final align = int.tryParse(
      alignStr.startsWith('0x') ? alignStr.substring(2) : alignStr,
      radix: 16,
    );
    if (align == null || align < 0x4000) {
      throw Exception(
        'LOAD segment alignment $alignStr is < 0x4000 (16 KB) in $soPath. '
        'Android 15 16 KB-page devices will reject this library.\n'
        'Line: $line',
      );
    }
  }

  logInfo('LOAD segments aligned to >=16 KB (${loadLines.length} segments)');
}

/// Returns the path to a usable readelf (llvm-readelf from the NDK preferred),
/// or `null` if none is available.
Future<String?> _findReadelf(String ndkPath) async {
  final hostTag = Platform.isMacOS ? 'darwin-x86_64' : 'linux-x86_64';
  final ndkReadelf =
      '$ndkPath/toolchains/llvm/prebuilt/$hostTag/bin/llvm-readelf';
  if (File(ndkReadelf).existsSync()) {
    return ndkReadelf;
  }

  for (final tool in ['llvm-readelf', 'readelf']) {
    final probe = await Process.run(Platform.isWindows ? 'where' : 'which', [
      tool,
    ]);
    if (probe.exitCode == 0) {
      final path = (probe.stdout as String).split('\n').first.trim();
      if (path.isNotEmpty) return path;
    }
  }
  return null;
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
