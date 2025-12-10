## 1.0.0

Initial release as an independent library. Based on [oqs](https://pub.dev/packages/oqs) by [bardiakz](https://github.com/bardiakz) with significant improvements and security fixes.

### Breaking Changes

- Renamed package from `oqs` to `liboqs`
- Removed `printSupportedKemAlgorithms()` and `printSupportedSignatureAlgorithms()` functions

### Added

- Pre-built native libraries for all platforms (no manual setup required)
- GitHub Actions CI/CD pipeline for automated testing
- Automated liboqs version tracking and updates via `LIBOQS_VERSION` file
- `LibOQSUtils.secureFreePointer()` for secure memory clearing (zeros memory before freeing)
- Algorithm name validation in `KEM.create()` and `Signature.create()`
- FFI plugin configuration for automatic native library bundling in Flutter apps
- Comprehensive test suite (44 tests)

### Changed

- Updated liboqs native library from 0.14.0 to 0.15.0
- Algorithm lists are now queried dynamically from liboqs (removed hardcoded lists)
- Reduced `maxAllocationSize` from 100MB to 3MB for safer memory allocation
- Simplified `pointerToUint8List()` implementation (direct copy instead of chunked)
- Consistent memory deallocation using `LibOQSUtils.freePointer()` throughout

### Fixed

- **Memory leak** in `getSupportedKemAlgorithms()` and `getSupportedSignatureAlgorithms()` - `toNativeUtf8()` allocations are now properly freed
- **Modulo bias** in `OQSRandom.generateInt()` - implemented rejection sampling for uniform distribution
- **Secret key exposure** - secret keys and shared secrets are now zeroed before freeing
- **Information leakage** - removed `print()` statements from cryptographic code paths
- **Unused validation** - `validateAlgorithmName()` is now called in `KEM.create()` and `Signature.create()`

### Security

- Completed comprehensive security audit
- All HIGH severity issues resolved (memory leaks, modulo bias)
- All MEDIUM severity issues resolved (secret key zeroing, print statements, validation)
- All LOW severity issues resolved (consistent memory handling)
