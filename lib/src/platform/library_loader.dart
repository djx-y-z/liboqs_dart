// Copyright (c) 2025 liboqs_dart authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import 'dart:ffi';
import 'dart:io';

/// Exception thrown when the liboqs library cannot be loaded.
class LibraryLoadException implements Exception {
  final String message;
  final dynamic cause;

  const LibraryLoadException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'LibraryLoadException: $message\nCaused by: $cause';
    }
    return 'LibraryLoadException: $message';
  }
}

/// Main class for loading the liboqs library.
///
/// With Dart Build Hooks (Dart 3.10+), the native library is automatically
/// downloaded and bundled with the application at build time. This loader
/// provides fallback strategies for special cases.
///
/// Loading strategies (in order):
/// 1. Explicit path (if provided via [explicitPath] parameter)
/// 2. Custom path (if set via [LibOQSLoader.customPath])
/// 3. Environment variable (LIBOQS_PATH)
/// 4. Native asset ID (Build Hooks automatically register the library)
/// 5. Platform-specific fallback paths
class LibOQSLoader {
  static DynamicLibrary? _cachedLibrary;

  /// Optional custom path to the library.
  ///
  /// Set this before calling [loadLibrary] to use a custom library path.
  /// Useful for testing or development scenarios.
  static String? customPath;

  /// Loads the liboqs dynamic library.
  ///
  /// With Build Hooks, the library is automatically bundled with the app.
  /// Falls back to system locations if needed.
  ///
  /// Parameters:
  /// - [explicitPath]: Direct path to the library file
  /// - [useCache]: Whether to cache and reuse the loaded library (default: true)
  /// - [envVarName]: Environment variable name for library path (default: 'LIBOQS_PATH')
  ///
  /// Returns a [DynamicLibrary] instance on success.
  /// Throws [LibraryLoadException] if all strategies fail.
  static DynamicLibrary loadLibrary({
    String? explicitPath,
    bool useCache = true,
    String envVarName = 'LIBOQS_PATH',
  }) {
    // Return cached library if available and caching is enabled
    if (useCache && _cachedLibrary != null) {
      return _cachedLibrary!;
    }

    DynamicLibrary? library;
    final attemptedPaths = <String>[];

    // Strategy 1: Explicit path
    if (explicitPath != null) {
      attemptedPaths.add('explicit: $explicitPath');
      library = _tryLoad(explicitPath);
    }

    // Strategy 2: Custom path
    if (library == null && customPath != null) {
      attemptedPaths.add('custom: $customPath');
      library = _tryLoad(customPath!);
    }

    // Strategy 3: Environment variable
    if (library == null) {
      final envPath = Platform.environment[envVarName];
      if (envPath != null && envPath.isNotEmpty) {
        attemptedPaths.add('env($envVarName): $envPath');
        library = _tryLoad(envPath);
      }
    }

    // Strategy 4: Platform-specific bundled library
    // Build Hooks bundle the library with the application
    if (library == null) {
      library = _tryBundledLibrary(attemptedPaths);
    }

    if (library == null) {
      throw LibraryLoadException(
        'Failed to load liboqs library for ${Platform.operatingSystem}. '
        'Attempted: ${attemptedPaths.join(', ')}. '
        'Ensure the application was built with Dart 3.10+ / Flutter 3.38+ '
        'which supports build hooks for automatic library bundling.',
      );
    }

    if (useCache) {
      _cachedLibrary = library;
    }
    return library;
  }

  /// Attempts to load the library from a specific path.
  static DynamicLibrary? _tryLoad(String path) {
    try {
      return DynamicLibrary.open(path);
    } catch (_) {
      return null;
    }
  }

  /// Returns platform-specific library file name.
  static String? _getLibraryName() {
    if (Platform.isMacOS || Platform.isIOS) return 'liboqs.dylib';
    if (Platform.isLinux || Platform.isAndroid) return 'liboqs.so';
    if (Platform.isWindows) return 'oqs.dll';
    return null;
  }

  /// Tries to load the library from CLI-specific locations.
  ///
  /// For JIT mode (dart run): .dart_tool/native_assets/ or .dart_tool/lib/
  /// For AOT mode (dart compile exe): ../lib/{libName} relative to executable
  static DynamicLibrary? _tryCLILibrary(List<String> attemptedPaths) {
    final libName = _getLibraryName();
    if (libName == null) return null;

    // Check if running as AOT compiled executable
    // JIT mode: executable is dart SDK binary (contains /dart-sdk/ or ends with /dart)
    // AOT mode: executable is user's compiled binary
    final resolvedExe = Platform.resolvedExecutable;
    final exeName = resolvedExe.split(Platform.pathSeparator).last.toLowerCase();
    final isJIT = exeName == 'dart' ||
        exeName == 'dart.exe' ||
        resolvedExe.contains('dart-sdk') ||
        resolvedExe.contains('flutter${Platform.pathSeparator}bin');
    final isAOT = !isJIT;

    if (isAOT) {
      // AOT mode: library is in ../lib/ or lib/ relative to executable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final aotPaths = [
        '$exeDir/../lib/$libName',
        '$exeDir/lib/$libName',
        '$exeDir/$libName',
      ];
      for (final path in aotPaths) {
        attemptedPaths.add('cli-aot: $path');
        final lib = _tryLoad(path);
        if (lib != null) return lib;
      }
    } else {
      // JIT mode: library is in .dart_tool/native_assets/ relative to project
      final projectDir = Directory.current.path;
      final arch = _getHostArch();
      final os = Platform.operatingSystem;

      final jitPaths = [
        // Dart 3.10+ native assets location
        '$projectDir/.dart_tool/native_assets/$os\_$arch/$libName',
        '$projectDir/.dart_tool/native_assets/$os/$libName',
        // Legacy location
        '$projectDir/.dart_tool/lib/$libName',
        // Relative to project
        '$projectDir/lib/$libName',
        '$projectDir/$libName',
      ];

      for (final path in jitPaths) {
        attemptedPaths.add('cli-jit: $path');
        final lib = _tryLoad(path);
        if (lib != null) return lib;
      }
    }

    return null;
  }

  /// Detect host architecture for native assets path
  static String _getHostArch() {
    // Use Dart's Platform to detect architecture
    // This is a simplified detection - in practice the arch comes from the build
    if (Platform.version.contains('arm64') ||
        Platform.version.contains('aarch64')) {
      return 'arm64';
    }
    return 'x64';
  }

  /// Attempts to load the bundled library based on platform.
  ///
  /// Build Hooks bundle the library with the application.
  /// Each platform has different conventions for bundled libraries.
  static DynamicLibrary? _tryBundledLibrary(List<String> attemptedPaths) {
    // Strategy 4a: CLI-specific paths (JIT and AOT)
    final cliLib = _tryCLILibrary(attemptedPaths);
    if (cliLib != null) return cliLib;

    // Strategy 4b: Platform-specific bundled library (Flutter)
    if (Platform.isMacOS) {
      // macOS: Framework format (Flutter converts liboqs.dylib -> oqs.framework/oqs)
      const macOSPaths = [
        '@rpath/oqs.framework/oqs',
        'oqs.framework/oqs',
        '@loader_path/../Frameworks/oqs.framework/oqs',
        '@rpath/liboqs.framework/liboqs',
        'liboqs.dylib',
        '@rpath/liboqs.dylib',
      ];
      for (final path in macOSPaths) {
        attemptedPaths.add('macos: $path');
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
    } else if (Platform.isLinux) {
      // Check if this is a Flutter/AOT app (not running via dart command)
      final resolvedExe = Platform.resolvedExecutable;
      final exeName = resolvedExe.split(Platform.pathSeparator).last.toLowerCase();
      final isFlutterOrAOT = exeName != 'dart' &&
          !resolvedExe.contains('dart-sdk') &&
          !resolvedExe.contains('flutter${Platform.pathSeparator}bin');

      if (isFlutterOrAOT) {
        // Flutter/AOT Linux: library is in lib/ relative to executable
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final flutterPaths = [
          // Flutter Linux bundle: bundle/lib/liboqs.so
          '$exeDir/lib/liboqs.so',
          // Alternative structure: executable in bin/, library in lib/
          '$exeDir/../lib/liboqs.so',
        ];
        for (final path in flutterPaths) {
          attemptedPaths.add('linux-flutter: $path');
          try {
            return DynamicLibrary.open(path);
          } catch (_) {
            continue;
          }
        }
      }

      // System library search (works for both CLI and Flutter)
      const systemPaths = ['liboqs.so', './liboqs.so', 'lib/liboqs.so'];
      for (final path in systemPaths) {
        attemptedPaths.add('linux: $path');
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
    } else if (Platform.isWindows) {
      // Check if this is a Flutter/AOT app (not running via dart command)
      final resolvedExe = Platform.resolvedExecutable;
      final exeName = resolvedExe.split(Platform.pathSeparator).last.toLowerCase();
      final isFlutterOrAOT = exeName != 'dart.exe' &&
          !resolvedExe.contains('dart-sdk') &&
          !resolvedExe.contains('flutter${Platform.pathSeparator}bin');

      if (isFlutterOrAOT) {
        // Flutter/AOT Windows: DLL is next to executable
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final flutterPaths = [
          '$exeDir/oqs.dll',
          '$exeDir/../lib/oqs.dll',
        ];
        for (final path in flutterPaths) {
          attemptedPaths.add('windows-flutter: $path');
          try {
            return DynamicLibrary.open(path);
          } catch (_) {
            continue;
          }
        }
      }

      // System DLL search (works for both CLI and Flutter)
      const systemPaths = ['oqs.dll', './oqs.dll'];
      for (final path in systemPaths) {
        attemptedPaths.add('windows: $path');
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
    } else if (Platform.isAndroid) {
      attemptedPaths.add('android: liboqs.so');
      try {
        return DynamicLibrary.open('liboqs.so');
      } catch (_) {
        // Fall through
      }
    } else if (Platform.isIOS) {
      // iOS: Framework format (Flutter converts liboqs.dylib -> oqs.framework/oqs)
      const iOSPaths = [
        '@rpath/oqs.framework/oqs',
        'oqs.framework/oqs',
        '@loader_path/Frameworks/oqs.framework/oqs',
        '@rpath/liboqs.framework/liboqs',
      ];
      for (final path in iOSPaths) {
        attemptedPaths.add('ios: $path');
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
    }

    return null;
  }

  /// Clears the cached library, forcing a fresh load on next call.
  static void clearCache() {
    _cachedLibrary = null;
  }

  /// Returns whether a library is currently cached.
  static bool get hasCachedLibrary => _cachedLibrary != null;
}
