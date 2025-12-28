import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings/liboqs_bindings.dart' as oqs;
import 'exception.dart';

/// Thread-safe base class for liboqs functionality
class LibOQSBase {
  static bool _initialized = false;
  static final Map<int, bool> _threadInitialized = {};

  /// Safe initialization with comprehensive error handling
  static void init() {
    if (_initialized) return;

    try {
      // Validate library is loaded by calling OQS_version
      final testPtr = oqs.OQS_version();
      // coverage:ignore-start
      if (testPtr == nullptr) {
        throw LibOQSException('LibOQS library appears to be invalid');
      }
      // coverage:ignore-end

      // Initialize the library
      oqs.OQS_init();
      _initialized = true;

      // Mark current thread as initialized
      final threadId = Isolate.current.hashCode;
      _threadInitialized[threadId] = true;
      // coverage:ignore-start
    } catch (e) {
      _initialized = false;
      throw LibOQSException('Failed to initialize LibOQS: $e');
    }
    // coverage:ignore-end
  }

  /// Safe cleanup with error handling
  static void cleanup() {
    if (!_initialized) return;

    try {
      // Clean up current thread first
      cleanupThread();

      // Then destroy the library
      oqs.OQS_destroy();
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
        oqs.OQS_thread_stop();
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
      final versionPtr = oqs.OQS_version();
      // coverage:ignore-start
      if (versionPtr == nullptr) {
        throw LibOQSException('Failed to get LibOQS version pointer');
      }
      // coverage:ignore-end

      // Validate the pointer before dereferencing
      final version = versionPtr.cast<Utf8>().toDartString();
      // coverage:ignore-start
      if (version.isEmpty) {
        throw LibOQSException('LibOQS version string is empty');
      }
      // coverage:ignore-end

      return version;
      // coverage:ignore-start
    } catch (e) {
      throw LibOQSException('Error getting LibOQS version: $e');
    }
    // coverage:ignore-end
  }

  /// Check if library is properly initialized
  static bool get isInitialized => _initialized;
}
