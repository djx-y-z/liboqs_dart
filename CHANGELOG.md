# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `LibOQSUtils.constantTimeEquals()` for timing-safe byte array comparison (prevents timing attacks)
- `LibOQSUtils.zeroMemory()` for secure memory zeroing using native `OQS_MEM_cleanse` (compiler-optimization resistant)
- `clearSecrets()` method to `KEMKeyPair`, `KEMEncapsulationResult`, and `SignatureKeyPair` for explicit secret zeroing
- Safe getters: `publicKeyBase64`, `publicKeyHex`, `ciphertextBase64`, `ciphertextHex` (don't expose secrets)
- Export `LibOQSUtils` from main library entry point
- Security documentation in SECURITY.md, README.md, and CLAUDE.md
- **Finalizers** for automatic secret zeroing on garbage collection (`KEMKeyPair`, `KEMEncapsulationResult`, `SignatureKeyPair`)
- SHA256 checksum verification for native library downloads in build hooks (supply chain security)

### Changed

- `LibOQSUtils.secureFreePointer()` now uses native `OQS_MEM_secure_free` instead of manual zeroing
- `LibOQSUtils.constantTimeEquals()` now performs constant-time length comparison (prevents length oracle attacks)
- `LibOQSUtils.constantTimeEquals()` now uses `secureFreePointer()` for temporary buffers
- `clearSecrets()` and Finalizers now use `OQS_MEM_cleanse` via centralized `zeroMemory()` function
- Added documentation explaining silent failure behavior in `secureFreePointer()` (by design for cryptographic libraries)

### Fixed

- `dispose()` operation order in KEM and Signature classes (free → detach → flag) to prevent memory leaks on exceptions
- Null pointer checks for native function pointers before calling `asFunction()`
- `OQSRandom.generateBytes()` now uses `secureFreePointer` for sensitive data
- Added explicit `nullptr` check in `KEM.generateKeyPairDerand()` for `keypair_derand` function pointer
- Added signature length validation in `Signature.verify()` (empty check and max length check)
- `OQSRandom.generateInt()` now has retry limit to prevent potential infinite loops in rejection sampling

### Security

- Added security warnings to `toStrings()` and `toHexStrings()` methods that expose secret keys
- Examples updated to use `constantTimeEquals()` instead of loop-based comparison
- Defense-in-depth: Finalizers automatically zero secrets if user forgets to call `clearSecrets()`
- Build hooks now verify SHA256 checksums of downloaded native libraries (prevents supply chain attacks)

## [1.0.3] - 2025-12-18

### Added

- Add support "@Native" annotation instead use library loader class
- Add "NATIVE_BUILD" file to manage build number of native library
- Add settings for code formatter

## [1.0.2] - 2025-12-14

### Added

- Linux ARM64 (aarch64) platform support for native libraries
- Updated README platform support table with architecture details

### Fixed

- Library loading on Linux and Windows Flutter desktop apps (paths relative to executable)
- Library loading for CLI applications in both JIT (`dart run`) and AOT (`dart build cli`) modes
- AOT detection logic no longer incorrectly triggers on project paths containing "dart" substring

## [1.0.1] - 2025-12-14

### Changed

- Native library releases now use `liboqs-{version}` tag format instead of `v{version}` to avoid conflicts with Dart package version tags

### Fixed

- Windows CI build: fixed FVM path handling in Git Bash environment

## [1.0.0] - 2025-12-13

### Added

- Pre-built native libraries for all platforms (iOS, Android, macOS, Linux, Windows)
- Key Encapsulation Mechanisms (KEM): ML-KEM, Kyber, Classic McEliece, FrodoKEM, HQC, NTRU
- Digital Signatures: ML-DSA, SLH-DSA, Falcon, SPHINCS+, MAYO, CROSS
- Cryptographically secure random number generation (`OQSRandom`)
- Automatic native library bundling via FFI plugin configuration
- `LibOQS.init()` for optional library pre-initialization
- `LibOQS.getSupportedKEMAlgorithms()` and `LibOQS.getSupportedSignatureAlgorithms()` for runtime algorithm discovery
- `LibOQS.isKEMSupported()` and `LibOQS.isSignatureSupported()` for algorithm availability checks
- Algorithm name validation in `KEM.create()` and `Signature.create()`
- `LibOQSUtils.secureFreePointer()` for secure memory clearing (zeros memory before freeing)
- Comprehensive test suite (44 tests)
- GitHub Actions CI/CD pipeline for automated testing and publishing
- Automated liboqs version tracking via `LIBOQS_VERSION` file
- Cross-platform build scripts for native library compilation
- Example Flutter application demonstrating all features

### Security

- Secret keys are automatically zeroed before memory is freed
- Based on liboqs 0.15.0 with NIST-standardized algorithms (FIPS 203, 204, 205)

[Unreleased]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/djx-y-z/liboqs_dart/releases/tag/v1.0.0
