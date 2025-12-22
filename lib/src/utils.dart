import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/liboqs_bindings.dart' as oqs;
import 'exception.dart';

/// Memory-safe utility class with extensive validation
class LibOQSUtils {
  /// Maximum allowed allocation size (3MB)
  /// Sufficient for largest PQ keys (Classic McEliece ~1.3MB)
  static const int maxAllocationSize = 3 * 1024 * 1024;

  /// Convert Uint8List to pointer with safety checks
  static Pointer<Uint8> uint8ListToPointer(Uint8List data) {
    if (data.isEmpty) {
      throw ArgumentError('Data cannot be empty');
    }

    if (data.length > maxAllocationSize) {
      throw LibOQSException(
        'Data too large: ${data.length} bytes (max: $maxAllocationSize)',
      );
    }

    Pointer<Uint8>? ptr;
    try {
      ptr = calloc<Uint8>(data.length);
      if (ptr == nullptr) {
        throw LibOQSException('Failed to allocate ${data.length} bytes');
      }

      // Validate the pointer before using it
      final nativeData = ptr.asTypedList(data.length);
      nativeData.setAll(0, data);

      return ptr;
    } catch (e) {
      if (ptr != null && ptr != nullptr) {
        try {
          calloc.free(ptr);
        } catch (_) {}
      }
      throw LibOQSException('Error converting Uint8List to pointer: $e');
    }
  }

  /// Convert pointer to Uint8List with extensive validation
  static Uint8List pointerToUint8List(Pointer<Uint8> ptr, int length) {
    if (ptr == nullptr) {
      throw LibOQSException('Cannot convert null pointer to Uint8List');
    }

    if (length <= 0) {
      return Uint8List(0);
    }

    if (length > maxAllocationSize) {
      throw LibOQSException(
        'Length too large: $length bytes (max: $maxAllocationSize)',
      );
    }

    try {
      // Create new list and copy data
      final data = Uint8List(length);
      final sourceData = ptr.asTypedList(length);
      data.setAll(0, sourceData);
      return data;
    } catch (e) {
      throw LibOQSException(
        'Error copying data from pointer (length: $length): $e',
      );
    }
  }

  /// Allocate memory with safety checks
  static Pointer<Uint8> allocateBytes(int size) {
    if (size <= 0) {
      throw ArgumentError('Size must be positive, got: $size');
    }

    if (size > maxAllocationSize) {
      throw LibOQSException(
        'Allocation too large: $size bytes (max: $maxAllocationSize)',
      );
    }

    try {
      final ptr = calloc<Uint8>(size);
      if (ptr == nullptr) {
        throw LibOQSException('Failed to allocate $size bytes - out of memory');
      }

      // Initialize memory to zero for safety
      final data = ptr.asTypedList(size);
      data.fillRange(0, size, 0);

      return ptr;
    } catch (e) {
      throw LibOQSException('Error allocating $size bytes: $e');
    }
  }

  /// Safe pointer deallocation
  static void freePointer(Pointer? ptr) {
    if (ptr == null || ptr == nullptr) return;

    try {
      calloc.free(ptr);
    } catch (_) {
      // Silent fail - cleanup errors should not leak to logs
    }
  }

  /// Securely free memory containing sensitive data (zeros before freeing)
  ///
  /// This is critical for secret keys, shared secrets, and other sensitive data.
  /// The memory is zeroed before freeing to prevent data recovery from freed memory.
  ///
  /// Uses liboqs `OQS_MEM_secure_free` which is designed to resist compiler
  /// optimizations that might remove the zeroing operation.
  static void secureFreePointer(Pointer? ptr, int length) {
    if (ptr == null || ptr == nullptr || length <= 0) return;

    try {
      // Use liboqs secure free which is designed to resist compiler optimizations
      oqs.OQS_MEM_secure_free(ptr.cast<Void>(), length);
    } catch (_) {
      // Fallback: manual zeroing + free if OQS_MEM_secure_free fails
      _fallbackSecureFree(ptr, length);
    }
  }

  /// Fallback secure free implementation using manual zeroing
  static void _fallbackSecureFree(Pointer ptr, int length) {
    try {
      // Zero the memory before freeing
      // Using explicit loop to reduce chance of compiler optimization
      final data = ptr.cast<Uint8>().asTypedList(length);
      for (int i = 0; i < length; i++) {
        data[i] = 0;
      }
    } catch (_) {
      // If zeroing fails, still try to free
    }

    try {
      calloc.free(ptr);
    } catch (_) {
      // Silent fail for cleanup
    }
  }

  /// Constant-time comparison of two byte arrays
  ///
  /// This function compares two byte arrays in constant time to prevent
  /// timing attacks. It uses liboqs `OQS_MEM_secure_bcmp` which is designed
  /// to be resistant to timing side-channel attacks.
  ///
  /// Returns `true` if the arrays are equal, `false` otherwise.
  /// If arrays have different lengths, returns `false`.
  ///
  /// Example:
  /// ```dart
  /// final isEqual = LibOQSUtils.constantTimeEquals(secret1, secret2);
  /// ```
  static bool constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }

    if (a.isEmpty) {
      return true;
    }

    final ptrA = uint8ListToPointer(a);
    final ptrB = uint8ListToPointer(b);

    try {
      // OQS_MEM_secure_bcmp returns 0 if equal, non-zero if different
      final result = oqs.OQS_MEM_secure_bcmp(
        ptrA.cast<Void>(),
        ptrB.cast<Void>(),
        a.length,
      );
      return result == 0;
    } finally {
      freePointer(ptrA);
      freePointer(ptrB);
    }
  }

  /// Validate algorithm name
  static void validateAlgorithmName(String name) {
    if (name.isEmpty) {
      throw ArgumentError('Algorithm name cannot be empty');
    }

    if (name.length > 256) {
      throw ArgumentError('Algorithm name too long: ${name.length} characters');
    }

    // Check for basic validity
    if (!RegExp(r'^[a-zA-Z0-9\-\+_]+$').hasMatch(name)) {
      throw ArgumentError('Algorithm name contains invalid characters: $name');
    }
  }
}
