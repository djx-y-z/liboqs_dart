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

    // Strategy 4: System/bundled location (Build Hooks)
    // The library is bundled by build hooks and should be found automatically
    if (library == null) {
      attemptedPaths.add('system: ${_getSystemLibraryName()}');
      library = _trySystemLoad();
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

  /// Attempts to load the library from system/bundled locations.
  ///
  /// Build Hooks place the library in platform-specific locations that
  /// [DynamicLibrary.open] can find automatically.
  static DynamicLibrary? _trySystemLoad() {
    try {
      if (Platform.isIOS) {
        // iOS: Framework bundled by build hooks
        return DynamicLibrary.open('liboqs.framework/liboqs');
      } else {
        // All other platforms: Build hooks bundle the library
        // so DynamicLibrary.open can find it by name
        return DynamicLibrary.open(_getSystemLibraryName());
      }
    } catch (_) {
      return null;
    }
  }

  /// Returns the platform-specific library filename.
  static String _getSystemLibraryName() {
    if (Platform.isWindows) {
      return 'oqs.dll';
    } else if (Platform.isLinux || Platform.isAndroid) {
      return 'liboqs.so';
    } else if (Platform.isMacOS || Platform.isIOS) {
      return 'liboqs.dylib';
    } else {
      throw UnsupportedError(
        'Platform ${Platform.operatingSystem} is not supported',
      );
    }
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
