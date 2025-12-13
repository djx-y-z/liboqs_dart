import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings/liboqs_bindings.dart';
import 'exception.dart';
import 'platform/library_loader.dart';

/// Thread-safe base class for liboqs functionality
class LibOQSBase {
  static DynamicLibrary? _lib;
  static LibOQSBindings? _bindings;
  static bool _initialized = false;
  static final Map<int, bool> _threadInitialized = {};

  /// Get the library instance with validation
  static DynamicLibrary get lib {
    if (_lib == null) {
      try {
        _lib = LibOQSLoader.loadLibrary(useCache: true);
      } catch (e) {
        throw LibOQSException('Failed to load LibOQS library: $e');
      }
    }
    return _lib!;
  }

  /// Get the liboqs bindings instance with validation
  static LibOQSBindings get bindings {
    if (_bindings == null) {
      try {
        _bindings = LibOQSBindings(lib);
      } catch (e) {
        throw LibOQSException('Failed to create LibOQS bindings: $e');
      }
    }
    return _bindings!;
  }

  /// Safe initialization with comprehensive error handling
  static void init() {
    if (_initialized) return;

    try {
      // Validate library is loaded
      final testPtr = bindings.OQS_version();
      if (testPtr == nullptr) {
        throw LibOQSException('LibOQS library appears to be invalid');
      }

      // Initialize the library
      bindings.OQS_init();
      _initialized = true;

      // Mark current thread as initialized
      final threadId = Isolate.current.hashCode;
      _threadInitialized[threadId] = true;
    } catch (e) {
      _initialized = false;
      throw LibOQSException('Failed to initialize LibOQS: $e');
    }
  }

  /// Safe cleanup with error handling
  static void cleanup() {
    if (!_initialized) return;

    try {
      // Clean up current thread first
      cleanupThread();

      // Then destroy the library
      bindings.OQS_destroy();
    } catch (_) {
      // Silent fail - cleanup errors should not leak to logs
    } finally {
      _initialized = false;
      _threadInitialized.clear();
    }
  }

  /// Clean up thread-specific resources
  static void cleanupThread() {
    final threadId = Isolate.current.hashCode;
    if (_threadInitialized[threadId] == true) {
      try {
        bindings.OQS_thread_stop();
        _threadInitialized[threadId] = false;
      } catch (_) {
        // Silent fail - cleanup errors should not leak to logs
      }
    }
  }

  /// Get version with comprehensive error handling
  static String getVersion() {
    init(); // Auto-initialize if needed

    try {
      final versionPtr = bindings.OQS_version();
      if (versionPtr == nullptr) {
        throw LibOQSException('Failed to get LibOQS version pointer');
      }

      // Validate the pointer before dereferencing
      final version = versionPtr.cast<Utf8>().toDartString();
      if (version.isEmpty) {
        throw LibOQSException('LibOQS version string is empty');
      }

      return version;
    } catch (e) {
      throw LibOQSException('Error getting LibOQS version: $e');
    }
  }

  /// Check if library is properly initialized
  static bool get isInitialized => _initialized;
}
