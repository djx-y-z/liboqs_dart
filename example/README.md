# liboqs Example

Interactive Flutter application demonstrating post-quantum cryptography with the `liboqs` package.

## Features

- **Key Encapsulation (KEM)** - ML-KEM-768 key generation, encapsulation, and decapsulation
- **Digital Signatures** - ML-DSA-65 signing and verification
- **Random Generation** - Cryptographically secure random bytes, integers, and shuffling
- **Algorithm Browser** - View all supported KEM and signature algorithms

## Running the Example

```bash
cd example
flutter run
```

Works on all platforms: iOS, Android, macOS, Linux, Windows.

## No Setup Required

The `liboqs` package includes pre-built native libraries for all platforms. Simply add the dependency:

```yaml
dependencies:
  liboqs: ^1.0.0
```

No manual library compilation or path configuration needed.

## Learn More

- [liboqs package on pub.dev](https://pub.dev/packages/liboqs)
- [liboqs GitHub repository](https://github.com/djx-y-z/liboqs_dart)
- [Open Quantum Safe project](https://openquantumsafe.org/)
