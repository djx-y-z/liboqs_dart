---
name: add-crypto-api
description: Add new cryptographic API to liboqs_dart. Use when implementing new KEM algorithms, signature schemes, adding new cryptographic features, or extending the library API.
---

# Add New Cryptographic API

Checklist and templates for adding new cryptographic functionality to liboqs_dart.

## Pre-Implementation Checklist

- [ ] API exists in liboqs C library
- [ ] Bindings exist in `lib/src/bindings/liboqs_bindings.dart`
- [ ] If not, run `make regen` first

## Implementation Checklist

### 1. Create Main Class

File: `lib/src/{feature}.dart`

```dart
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'base.dart';
import 'bindings/liboqs_bindings.dart' as oqs;
import 'exception.dart';
import 'utils.dart';

// Finalizer for native resource cleanup
final Finalizer<Pointer<oqs.OQS_FEATURE>> _featureFinalizer = Finalizer(
  (ptr) => oqs.OQS_FEATURE_free(ptr),
);

// Finalizer for zeroing secrets
final Finalizer<Uint8List> _secretDataFinalizer = Finalizer((data) {
  LibOQSUtils.zeroMemory(data);
});

class Feature {
  late final Pointer<oqs.OQS_FEATURE> _ptr;
  final String algorithmName;
  bool _disposed = false;

  Feature._(this._ptr, this.algorithmName) {
    _featureFinalizer.attach(this, _ptr, detach: this);
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('Instance has been disposed');
  }

  static Feature create(String algorithmName) {
    LibOQSBase.init();
    LibOQSUtils.validateAlgorithmName(algorithmName);
    // ... implementation
  }

  void dispose() {
    if (!_disposed) {
      oqs.OQS_FEATURE_free(_ptr);
      _featureFinalizer.detach(this);
      _disposed = true;
    }
  }
}
```

### 2. Create Data Classes

For any class holding secrets:

```dart
class FeatureKeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;  // SECRET!

  FeatureKeyPair({required this.publicKey, required this.secretKey}) {
    // Attach finalizer for auto-cleanup
    _secretDataFinalizer.attach(this, secretKey, detach: this);
  }

  /// Zero secrets immediately
  void clearSecrets() {
    LibOQSUtils.zeroMemory(secretKey);
  }

  /// Safe: public key only
  String get publicKeyBase64 => base64Encode(publicKey);
  String get publicKeyHex => publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// **Security Warning:** Exports SECRET KEY!
  Map<String, String> toStrings() => {
    'publicKey': base64Encode(publicKey),
    'secretKey': base64Encode(secretKey),
  };
}
```

### 3. Export from Library

Edit `lib/liboqs.dart`:

```dart
export 'src/feature.dart';
```

### 4. Write Tests

File: `test/{feature}_test.dart`

```dart
import 'package:liboqs/liboqs.dart';
import 'package:test/test.dart';

void main() {
  group('Feature', () {
    late Feature feature;

    setUp(() {
      feature = Feature.create('Algorithm-Name');
    });

    tearDown(() {
      feature.dispose();
    });

    test('lists supported algorithms', () {
      final algorithms = Feature.getSupportedAlgorithms();
      expect(algorithms, isNotEmpty);
    });

    test('generates key pair', () {
      final keyPair = feature.generateKeyPair();
      expect(keyPair.publicKey, isNotEmpty);
      expect(keyPair.secretKey, isNotEmpty);

      // Cleanup secrets
      keyPair.clearSecrets();
    });

    test('throws on disposed instance', () {
      feature.dispose();
      expect(() => feature.someMethod(), throwsStateError);
    });
  });
}
```

### 5. Add Security Test

File: `test/security_test.dart` (add to existing)

```dart
test('Feature zeros secrets on clearSecrets()', () {
  final feature = Feature.create('Algorithm-Name');
  final keyPair = feature.generateKeyPair();

  final secretCopy = Uint8List.fromList(keyPair.secretKey);
  expect(keyPair.secretKey, equals(secretCopy));

  keyPair.clearSecrets();
  expect(keyPair.secretKey, everyElement(0));

  feature.dispose();
});
```

### 6. Update Documentation

Add to README.md if it's a major feature:

```markdown
## Feature Name

Description of the feature...

```dart
final feature = Feature.create('Algorithm-Name');
final keyPair = feature.generateKeyPair();
// ...
keyPair.clearSecrets();
feature.dispose();
```
```

## Security Requirements Checklist

- [ ] All secret data uses `secureFreePointer()` in native code
- [ ] All secret data classes have `clearSecrets()` method
- [ ] All secret data classes have `_secretDataFinalizer` attached
- [ ] All function pointers validated before `.asFunction()`
- [ ] All memory freed in `finally` blocks
- [ ] All methods exposing secrets have `/// **Security Warning:**` docs
- [ ] Public-key-only getters provided (`publicKeyBase64`, `publicKeyHex`)
- [ ] `dispose()` follows correct order: free → detach → flag

## Run Quality Checks

```bash
# Format code
make format

# Static analysis
make analyze ARGS="--fatal-infos"

# Run tests
make test

# Run specific test
make test ARGS="test/feature_test.dart"

# Security tests
make test ARGS="test/security_test.dart"
```

## Existing Implementations to Reference

| Feature | File | Description |
|---------|------|-------------|
| KEM | `lib/src/kem.dart` | Key Encapsulation Mechanism |
| Signature | `lib/src/signature.dart` | Digital Signatures |
| Random | `lib/src/random.dart` | Random Number Generation |

These files demonstrate all required patterns.
