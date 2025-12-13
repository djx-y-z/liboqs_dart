// Copyright (c) 2025 liboqs_dart authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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
/// 4. System/bundled location (Build Hooks automatically place the library here)
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

  /// Attempts to load the bundled library based on platform.
  ///
  /// Build Hooks bundle the library with the application.
  /// Each platform has different conventions for bundled libraries.
  static DynamicLibrary? _tryBundledLibrary(List<String> attemptedPaths) {
    // Try native asset ID first (works with Dart 3.10+ native assets)
    // This should work automatically when build hooks are properly configured
    attemptedPaths.add('native_asset: package:liboqs/liboqs');
    try {
      final lib = DynamicLibrary.open('package:liboqs/liboqs');
      // Verify the library works by looking up a known symbol
      lib.lookup<NativeFunction<Pointer<Utf8> Function()>>('OQS_version');
      return lib;
    } catch (e) {
      // Log error for debugging (visible in flutter run output)
      // ignore: avoid_print
      print('[liboqs] Native asset load failed: $e');
      // Fall through to platform-specific loading
    }

    // Platform-specific bundled library paths
    if (Platform.isMacOS) {
      // macOS: Libraries are bundled as frameworks
      // Try various paths that Flutter/macOS might use
      const macOSPaths = [
        'oqs.framework/oqs', // Framework in current directory
        '@rpath/oqs.framework/oqs', // Framework via rpath
        '@loader_path/../Frameworks/oqs.framework/oqs', // Relative to executable
        'liboqs.dylib', // Direct dylib
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
      // Linux: Libraries in lib directory or system paths
      const linuxPaths = [
        'liboqs.so',
        './liboqs.so',
        'lib/liboqs.so',
      ];
      for (final path in linuxPaths) {
        attemptedPaths.add('linux: $path');
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
    } else if (Platform.isWindows) {
      // Windows: DLLs in same directory as executable
      const windowsPaths = [
        'oqs.dll',
        './oqs.dll',
      ];
      for (final path in windowsPaths) {
        attemptedPaths.add('windows: $path');
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
    } else if (Platform.isAndroid) {
      // Android: Libraries in jniLibs, loaded by name
      attemptedPaths.add('android: liboqs.so');
      try {
        return DynamicLibrary.open('liboqs.so');
      } catch (_) {
        // Fall through
      }
    } else if (Platform.isIOS) {
      // iOS device: static linking (symbols in main executable)
      // iOS simulator: dynamic linking (dylib bundled in app)
      // Try both approaches since we can't easily detect device vs simulator at runtime

      // First try static linking (for device with statically linked library)
      // This must be tried first because on device, dynamic loading will fail
      attemptedPaths.add('ios: process (static linking)');
      try {
        final lib = DynamicLibrary.process();
        // Verify symbols exist
        lib.lookup<NativeFunction<Pointer<Utf8> Function()>>('OQS_version');
        // ignore: avoid_print
        print('[liboqs] Loaded via static linking (iOS device)');
        return lib;
      } catch (e) {
        // ignore: avoid_print
        print('[liboqs] Static linking failed: $e');
        // Fall through to dynamic loading
      }

      // Try dynamic loading (for simulator)
      const iOSPaths = [
        // Flutter native assets paths
        '@rpath/liboqs.dylib',
        '@executable_path/Frameworks/liboqs.dylib',
        '@loader_path/Frameworks/liboqs.dylib',
        // Framework paths
        'liboqs.framework/liboqs',
        '@rpath/liboqs.framework/liboqs',
        '@loader_path/Frameworks/liboqs.framework/liboqs',
        // Direct dylib
        'liboqs.dylib',
      ];
      for (final path in iOSPaths) {
        attemptedPaths.add('ios: $path');
        try {
          final lib = DynamicLibrary.open(path);
          // ignore: avoid_print
          print('[liboqs] Loaded from: $path');
          return lib;
        } catch (e) {
          // ignore: avoid_print
          print('[liboqs] Failed to load $path: $e');
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

/// Legacy function for backward compatibility.
@Deprecated('Use LibOQSLoader.loadLibrary() instead')
DynamicLibrary loadLibOQS() {
  return LibOQSLoader.loadLibrary();
}

/// Legacy function for backward compatibility with error handling.
@Deprecated('Use LibOQSLoader.loadLibrary() instead')
DynamicLibrary loadLibOQSWithErrorHandling() {
  return LibOQSLoader.loadLibrary();
}
