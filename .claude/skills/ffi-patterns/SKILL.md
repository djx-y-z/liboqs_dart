---
name: ffi-patterns
description: Dart FFI patterns and best practices for this project. Use when writing FFI code, working with native memory, creating wrappers, or implementing new native bindings.
---

# FFI Patterns for liboqs_dart

Patterns and templates for writing correct Dart FFI code in this project.

## Memory Allocation

### Allocate Bytes

```dart
final ptr = LibOQSUtils.allocateBytes(length);
try {
  // Use ptr...
} finally {
  LibOQSUtils.freePointer(ptr);  // or secureFreePointer for secrets
}
```

### Convert Uint8List to Pointer

```dart
final ptr = LibOQSUtils.uint8ListToPointer(data);
try {
  // Use ptr...
} finally {
  LibOQSUtils.freePointer(ptr);
}
```

### Convert Pointer to Uint8List

```dart
final result = LibOQSUtils.pointerToUint8List(ptr, length);
// Result is a copy - safe to free ptr after this
```

## String Handling

```dart
final namePtr = algorithmName.toNativeUtf8();
try {
  final result = oqs.OQS_KEM_new(namePtr.cast());
  // ...
} finally {
  LibOQSUtils.freePointer(namePtr);
}
```

## Wrapper Class Pattern

```dart
// Finalizer for automatic cleanup
final Finalizer<Pointer<oqs.OQS_KEM>> _kemFinalizer = Finalizer(
  (ptr) => oqs.OQS_KEM_free(ptr),
);

class KEM {
  late final Pointer<oqs.OQS_KEM> _ptr;
  bool _disposed = false;

  KEM._(this._ptr) {
    // Attach finalizer for GC cleanup
    _kemFinalizer.attach(this, _ptr, detach: this);
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('Instance has been disposed');
    }
  }

  // Factory constructor
  static KEM create(String algorithmName) {
    LibOQSBase.init();  // Auto-initialize library

    final namePtr = algorithmName.toNativeUtf8();
    try {
      final ptr = oqs.OQS_KEM_new(namePtr.cast());
      if (ptr == nullptr) {
        throw LibOQSException('Failed to create instance');
      }
      return KEM._(ptr);
    } finally {
      LibOQSUtils.freePointer(namePtr);
    }
  }

  // Dispose pattern
  void dispose() {
    if (!_disposed) {
      oqs.OQS_KEM_free(_ptr);      // 1. Free native memory
      _kemFinalizer.detach(this);   // 2. Detach finalizer
      _disposed = true;              // 3. Set flag
    }
  }
}
```

## Data Class with Secrets

```dart
final Finalizer<Uint8List> _secretFinalizer = Finalizer((data) {
  LibOQSUtils.zeroMemory(data);
});

class KeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  KeyPair({required this.publicKey, required this.secretKey}) {
    // Auto-zero secret on GC (defense-in-depth)
    _secretFinalizer.attach(this, secretKey, detach: this);
  }

  /// Zero secrets immediately (recommended)
  void clearSecrets() {
    LibOQSUtils.zeroMemory(secretKey);
  }

  /// Safe: only exposes public key
  String get publicKeyBase64 => base64Encode(publicKey);

  /// **Security Warning:** Exports SECRET KEY in plaintext!
  Map<String, String> toStrings() {
    return {
      'publicKey': base64Encode(publicKey),
      'secretKey': base64Encode(secretKey),
    };
  }
}
```

## Calling Native Functions

### From Struct Field

```dart
// 1. Validate function pointer
if (_ptr.ref.keypair == nullptr) {
  throw LibOQSException('Function pointer is null');
}

// 2. Convert to Dart function
final keypairFn = _ptr.ref.keypair.asFunction<
  int Function(Pointer<Uint8> publicKey, Pointer<Uint8> secretKey)
>();

// 3. Allocate output buffers
final publicKey = LibOQSUtils.allocateBytes(publicKeyLength);
final secretKey = LibOQSUtils.allocateBytes(secretKeyLength);

try {
  // 4. Call function
  final result = keypairFn(publicKey, secretKey);

  if (result != 0) {
    throw LibOQSException('Operation failed', result);
  }

  // 5. Copy results to Dart
  return KeyPair(
    publicKey: LibOQSUtils.pointerToUint8List(publicKey, publicKeyLength),
    secretKey: LibOQSUtils.pointerToUint8List(secretKey, secretKeyLength),
  );
} finally {
  // 6. Free native memory (secure for secrets!)
  LibOQSUtils.freePointer(publicKey);
  LibOQSUtils.secureFreePointer(secretKey, secretKeyLength);
}
```

### Direct Library Call

```dart
final count = oqs.OQS_KEM_alg_count();  // Simple - no cleanup needed

final namePtr = oqs.OQS_KEM_alg_identifier(i);
if (namePtr != nullptr) {
  final name = namePtr.cast<Utf8>().toDartString();
  // Don't free namePtr - it's a static string from library
}
```

## Error Handling

```dart
try {
  final result = nativeFunction(args);
  if (result != 0) {
    throw LibOQSException('Operation failed', result);
  }
} on LibOQSException {
  rethrow;  // Preserve our exceptions
} catch (e) {
  throw LibOQSException('Unexpected error: $e');
}
```

## Utilities Reference

| Method | Use For |
|--------|---------|
| `LibOQSUtils.allocateBytes(n)` | Allocate n bytes |
| `LibOQSUtils.freePointer(ptr)` | Free non-sensitive memory |
| `LibOQSUtils.secureFreePointer(ptr, len)` | Free sensitive memory (zeros first) |
| `LibOQSUtils.uint8ListToPointer(list)` | Copy Dart list to native |
| `LibOQSUtils.pointerToUint8List(ptr, len)` | Copy native to Dart list |
| `LibOQSUtils.zeroMemory(list)` | Zero a Dart Uint8List |
| `LibOQSUtils.constantTimeEquals(a, b)` | Compare secrets safely |
| `LibOQSUtils.validateAlgorithmName(name)` | Check algorithm name format |
