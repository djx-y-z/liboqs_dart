# liboqs - Post-Quantum Cryptography for Dart

[![pub package](https://img.shields.io/pub/v/liboqs.svg)](https://pub.dev/packages/liboqs)
[![CI](https://github.com/djx-y-z/liboqs_dart/actions/workflows/test.yml/badge.svg)](https://github.com/djx-y-z/liboqs_dart/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.10.0-brightgreen.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.38.0-blue.svg)](https://flutter.dev)
[![liboqs](https://img.shields.io/badge/liboqs-0.15.0-orange.svg)](https://github.com/open-quantum-safe/liboqs)

A Dart FFI wrapper for [liboqs](https://github.com/open-quantum-safe/liboqs), providing access to post-quantum cryptographic algorithms including key encapsulation mechanisms (KEMs), digital signatures, and cryptographically secure random number generation.

## Platform Support

|             | Android | iOS   | macOS  | Linux      | Windows |
|-------------|---------|-------|--------|------------|---------|
| **Support** | SDK 21+ | 12.0+ | 10.14+ | arm64, x64 | x64     |
| **Arch**    | arm64, armv7, x64 | arm64 | arm64, x64 | arm64, x64 | x64 |

## Features

- **Flutter & CLI Support**: Works with Flutter apps and standalone Dart CLI applications
- **Key Encapsulation (ML-KEM)**: NIST standardized (FIPS 203), plus Classic McEliece, FrodoKEM, HQC
- **Digital Signatures (ML-DSA, SLH-DSA)**: NIST standardized (FIPS 204, 205), plus Falcon, MAYO
- **Cryptographically Secure Random**: System-backed random number generation
- **Zero Configuration**: Pre-built native libraries included via Build Hooks
- **High Performance**: Direct FFI bindings with minimal overhead
- **Automated Updates**: Native libraries auto-rebuild when new liboqs versions are released

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  liboqs: ^1.0.3
```

## Quick Start

```dart
import 'package:liboqs/liboqs.dart';

void main() {
  // Initialize the library (optional but recommended for performance)
  LibOQS.init();

  // Key Encapsulation (ML-KEM)
  final kem = KEM.create('ML-KEM-768')!;
  final keyPair = kem.generateKeyPair();
  final encResult = kem.encapsulate(keyPair.publicKey);
  final sharedSecret = kem.decapsulate(encResult.ciphertext, keyPair.secretKey);
  kem.dispose();

  // Digital Signatures (ML-DSA)
  final sig = Signature.create('ML-DSA-65');
  final sigKeyPair = sig.generateKeyPair();
  final signature = sig.sign(message, sigKeyPair.secretKey);
  final isValid = sig.verify(message, signature, sigKeyPair.publicKey);
  sig.dispose();

  // Random Generation
  final randomBytes = OQSRandom.generateBytes(32);
  final randomInt = OQSRandom.generateInt(1, 100);
}
```

## Supported Algorithms

> **Note:** The native library is built with all algorithms enabled, including experimental ones.
> For production use, we recommend NIST-standardized algorithms (ML-KEM, ML-DSA, SLH-DSA).

### Key Encapsulation Mechanisms (KEMs)

| Algorithm | Security Level | Status |
|-----------|----------------|--------|
| ML-KEM-512, ML-KEM-768, ML-KEM-1024 | NIST Level 1/3/5 | FIPS 203 Standard |
| Kyber512, Kyber768, Kyber1024 | NIST Level 1/3/5 | Legacy (use ML-KEM) |
| HQC | Various | NIST Selected |
| Classic McEliece variants | Various | ISO consideration |
| FrodoKEM variants | Various | ISO consideration |
| NTRU, NTRU-Prime | Various | Not NIST selected |

### Digital Signatures

| Algorithm | Security Level | Status |
|-----------|----------------|--------|
| ML-DSA-44, ML-DSA-65, ML-DSA-87 | NIST Level 2/3/5 | FIPS 204 Standard |
| SLH-DSA variants | Various | FIPS 205 Standard |
| Falcon-512, Falcon-1024 | NIST Level 1/5 | NIST Selected |
| SPHINCS+ variants | Various | Deprecated (use SLH-DSA) |
| MAYO, CROSS, SNOVA, UOV | Various | Under NIST consideration |

### Listing Available Algorithms

```dart
// Get all supported algorithms at runtime
final kemAlgorithms = LibOQS.getSupportedKEMAlgorithms();
final sigAlgorithms = LibOQS.getSupportedSignatureAlgorithms();

// Check if specific algorithm is supported
print('ML-KEM-768 supported: ${LibOQS.isKEMSupported('ML-KEM-768')}');
print('ML-DSA-65 supported: ${LibOQS.isSignatureSupported('ML-DSA-65')}');
```

## API Reference

### Key Encapsulation (KEM)

```dart
import 'package:liboqs/liboqs.dart';

final kem = KEM.create('ML-KEM-768')!;

// Algorithm properties
print('Public key length: ${kem.publicKeyLength}');
print('Secret key length: ${kem.secretKeyLength}');
print('Ciphertext length: ${kem.ciphertextLength}');
print('Shared secret length: ${kem.sharedSecretLength}');

// Key generation
final keyPair = kem.generateKeyPair();

// Encapsulation (sender side)
final encResult = kem.encapsulate(keyPair.publicKey);
// encResult.ciphertext - send to recipient
// encResult.sharedSecret - use for encryption

// Decapsulation (recipient side)
final sharedSecret = kem.decapsulate(encResult.ciphertext, keyPair.secretKey);

// Clean up
kem.dispose();
```

### Digital Signatures

```dart
import 'package:liboqs/liboqs.dart';
import 'dart:convert';

final sig = Signature.create('ML-DSA-65');

// Algorithm properties
print('Public key length: ${sig.publicKeyLength}');
print('Secret key length: ${sig.secretKeyLength}');
print('Max signature length: ${sig.maxSignatureLength}');

// Key generation
final keyPair = sig.generateKeyPair();

// Sign message
final message = utf8.encode('Hello, post-quantum world!');
final signature = sig.sign(message, keyPair.secretKey);

// Verify signature
final isValid = sig.verify(message, signature, keyPair.publicKey);

// Clean up
sig.dispose();
```

### Random Number Generation

```dart
import 'package:liboqs/liboqs.dart';

// Generate random bytes
final randomBytes = OQSRandom.generateBytes(32);

// Generate cryptographic seed (32 bytes)
final seed = OQSRandom.generateSeed();

// Generate random integer in range [min, max)
final randomInt = OQSRandom.generateInt(1, 100);

// Generate random boolean
final randomBool = OQSRandom.generateBool();

// Generate random double in range [0, 1)
final randomDouble = OQSRandom.generateDouble();

// Cryptographically secure shuffle
final list = ['a', 'b', 'c', 'd', 'e'];
OQSRandom.shuffleList(list);
```

## Resource Management

### Basic Usage

```dart
final kem = KEM.create('ML-KEM-768')!;
// Use KEM...
kem.dispose(); // Clean up when done
```

### Performance Optimization

For better performance, initialize once at app start:

```dart
void main() {
  LibOQS.init(); // Recommended at app startup
  runApp(MyApp());
}
```

## Security Notes

**Recommended Algorithms:**
- **ML-KEM** (FIPS 203) - NIST standardized key encapsulation
- **ML-DSA** (FIPS 204) - NIST standardized digital signatures
- **SLH-DSA** (FIPS 205) - NIST standardized hash-based signatures
- Other algorithms may be experimental - validate against current security recommendations

**Best Practices:**
- Always call `dispose()` on KEM/Signature instances to free native resources
- Call `clearSecrets()` on key pairs when done to zero Dart memory
- Use `LibOQSUtils.constantTimeEquals()` for comparing secrets (prevents timing attacks)
- Use `OQSRandom.generateSeed()` for cryptographic key derivation
- Keep the library updated to the latest version
- Never log `toStrings()` or `toHexStrings()` output - they contain secret keys

```dart
// Secure usage example
final kem = KEM.create('ML-KEM-768');
final keyPair = kem.generateKeyPair();
final encResult = kem.encapsulate(keyPair.publicKey);
final sharedSecret = kem.decapsulate(encResult.ciphertext, keyPair.secretKey);

// Verify secrets match using constant-time comparison
final match = LibOQSUtils.constantTimeEquals(encResult.sharedSecret, sharedSecret);

// Clean up sensitive data
keyPair.clearSecrets();
encResult.clearSecrets();
kem.dispose();
```

## Acknowledgements

This library is based on [oqs](https://pub.dev/packages/oqs) by [bardiakz](https://github.com/bardiakz). We thank the original author for creating the initial Dart FFI bindings for liboqs.

This library would not be possible without [liboqs](https://github.com/open-quantum-safe/liboqs) by the [Open Quantum Safe](https://openquantumsafe.org/) project, which provides the underlying C implementations of post-quantum cryptographic algorithms.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

The bundled liboqs library is also licensed under MIT - see [LICENSE.liboqs](LICENSE.liboqs) for the Open Quantum Safe project license.

## Related Projects

- [liboqs](https://github.com/open-quantum-safe/liboqs) - The underlying C library
- [Open Quantum Safe](https://openquantumsafe.org/) - The OQS project
- [NIST Post-Quantum Cryptography](https://csrc.nist.gov/projects/post-quantum-cryptography) - NIST PQC standardization

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting issues or pull requests.

For major changes, please open an issue first to discuss what you would like to change.
