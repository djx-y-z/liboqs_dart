# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
