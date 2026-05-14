## [Unreleased]

### Fixed

- Android: native libraries are now built with LOAD segments aligned to 16 KB, so they load correctly on Android 15+ devices that use 16 KB memory pages ([#1](https://github.com/djx-y-z/liboqs_dart/issues/1)). The Android build script now passes `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384` to the linker and verifies alignment on the 64-bit ABIs via `llvm-readelf`/`readelf` after the build.

## [1.2.0] - 2026-02-07

### Changed

- Raised minimum iOS deployment target from 12.0 to 13.0 (matches Flutter 3.38.x minimum)
- Raised minimum macOS deployment target from 10.14 to 10.15 (matches Flutter 3.32+ minimum)

## [1.1.3] - 2026-02-07

### Fixed

- macOS x86_64 build deployment target lowered from 10.15 to 10.14 (matches podspec minimum)

## [1.1.2] - 2026-01-10

### Added

- Pre-commit git hook for format check and static analysis (configured via `make setup`)
- Multi-platform testing workflow (`test-reusable.yml`): Linux x86_64, Linux ARM64, macOS ARM64, Windows x86_64
- GitHub App token support for signed commits in CI workflows
- Skip tests for automated bot PRs (native libraries not yet built)
- `.claude/skills/` folder now included in repository and published package

### Changed

- `Signature.sign()` and `Signature.verify()` now allow empty messages (valid per FIPS 204 and liboqs)
- Simplified `check-liboqs-updates.yml` workflow: removed AI analysis, now only updates `native_version` in pubspec.yaml
- Removed `--ai`, `--no-ai`, `--bump`, `--no-changelog` flags from `check_updates.dart` (script now focuses on version checking only)
- Replaced `softprops/action-gh-release` with official `gh` CLI for release creation (build-liboqs.yml, publish.yml)
- Updated GitHub Actions: `peter-evans/create-pull-request` v8, `actions/create-github-app-token` v2, `ilammy/msvc-dev-cmd` v1.13.0
- Improved Windows FVM setup with PUB_CACHE detection and shell wrapper for Git Bash compatibility
- Native library release description simplified: removed "Usage" section, renamed "Archive Format" to "Platforms"

### Fixed

- Fixed version parsing in `build-liboqs.yml` workflow (use Dart script instead of grep for reliable parsing)
- Added checkout step to create-release job (required for gh CLI)
- FVM config changes are now discarded after setup to prevent unwanted modifications

### Removed

- `scripts/src/ai_analysis.dart` - AI-powered changelog generation removed
- `.github/prompts/ai-analysis-prompt.md` - AI prompt template removed

## [1.1.1] - 2026-01-02

### Added

- `analysis_options.yaml` with recommended lints and exclusions for auto-generated bindings
- `make doc` command for local API documentation generation

### Fixed

- `.pubignore` now includes `CONTRIBUTING.md` in published package (needed for pub.dev links)
- `.pubignore` now excludes generated `doc/` directory

### Changed

- Refactored CI update workflow: moved AI analysis from bash to Dart script
- Simplified `check-liboqs-updates.yml` workflow (~540 → ~190 lines)
- Added `--ai`, `--no-ai`, `--ci` flags to `check_updates.dart` script
- Script now writes directly to `GITHUB_OUTPUT` in CI mode (no jq parsing needed)
- `make check` and `make combine` now create `.skip_liboqs_hook` to prevent build hooks during execution
- `make coverage` now uses `--check-ignore` flag (respects `coverage:ignore` annotations)
- CI test workflow now uses `make coverage` instead of direct commands
- Removed `print()` calls from tests (follow Dart best practices)
- `build-liboqs.yml` workflow now skips build if release already exists (prevents unnecessary rebuilds when only package version changes)

## [1.1.0] - 2025-12-28

### Added

- `LibOQSUtils.constantTimeEquals()` for timing-safe byte array comparison (prevents timing attacks)
- `LibOQSUtils.zeroMemory()` for secure memory zeroing using native `OQS_MEM_cleanse` (compiler-optimization resistant)
- `clearSecrets()` method to `KEMKeyPair`, `KEMEncapsulationResult`, and `SignatureKeyPair` for explicit secret zeroing
- Safe getters: `publicKeyBase64`, `publicKeyHex`, `ciphertextBase64`, `ciphertextHex` (don't expose secrets)
- Export `LibOQSUtils` from main library entry point
- Security documentation in SECURITY.md, README.md, and CLAUDE.md
- **Finalizers** for automatic secret zeroing on garbage collection (`KEMKeyPair`, `KEMEncapsulationResult`, `SignatureKeyPair`)
- SHA256 checksum verification for native library downloads in build hooks (supply chain security)
- Comprehensive test coverage (100%): `exception_test.dart`, `utils_test.dart`, extended KEM/Signature/Random tests
- Test coverage reporting with GitHub Gist badge
- `make coverage` command for local coverage testing
- Centralized `get_version.dart` script for version parsing
- `runDart/runDartOrFail` helpers in `common.dart` for consistent FVM usage
- `crypto` package dependency for SHA256 checksum verification

### Changed

- `LibOQSUtils.secureFreePointer()` now uses native `OQS_MEM_secure_free` instead of manual zeroing
- `LibOQSUtils.constantTimeEquals()` now performs constant-time length comparison (prevents length oracle attacks)
- `LibOQSUtils.constantTimeEquals()` now uses `secureFreePointer()` for temporary buffers
- `clearSecrets()` and Finalizers now use `OQS_MEM_cleanse` via centralized `zeroMemory()` function
- Added documentation explaining silent failure behavior in `secureFreePointer()` (by design for cryptographic libraries)
- Native library version moved from `LIBOQS_VERSION`/`NATIVE_BUILD` files to `pubspec.yaml` (centralized version management)
- All scripts now read version from `pubspec.yaml` via `get_version.dart`
- `make regen` now creates `.skip_liboqs_hook` marker file to prevent Build Hooks during regeneration
- `regenerate_bindings.dart` now uses FVM Dart when available

### Fixed

- `dispose()` operation order in KEM and Signature classes (free → detach → flag) to prevent memory leaks on exceptions
- Null pointer checks for native function pointers before calling `asFunction()`
- `OQSRandom.generateBytes()` now uses `secureFreePointer` for sensitive data
- Added explicit `nullptr` check in `KEM.generateKeyPairDerand()` for `keypair_derand` function pointer
- Added signature length validation in `Signature.verify()` (empty check and max length check)
- `OQSRandom.generateInt()` now has retry limit to prevent potential infinite loops in rejection sampling
- CI workflow now uses `--check-ignore` flag for coverage reporting (respects `coverage:ignore` annotations)
- Regex replacement bug in `check_updates.dart` (`replaceFirst` → `replaceFirstMapped`)

### Security

- Added security warnings to `toStrings()` and `toHexStrings()` methods that expose secret keys
- Examples updated to use `constantTimeEquals()` instead of loop-based comparison
- Defense-in-depth: Finalizers automatically zero secrets if user forgets to call `clearSecrets()`
- Build hooks now verify SHA256 checksums of downloaded native libraries (prevents supply chain attacks)

### Removed

- `LIBOQS_VERSION` file (version now in `pubspec.yaml`)
- `NATIVE_BUILD` file (build number now in `pubspec.yaml`)

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

[Unreleased]: https://github.com/djx-y-z/liboqs_dart/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/djx-y-z/liboqs_dart/releases/tag/v1.0.0
