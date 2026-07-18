## [2.0.0] - 2026-07-18

### For Users

#### ✨ Highlights

- **Bundled liboqs upgraded 0.15.0 → 0.16.0 (breaking)** — includes upstream
  security fixes (see Security) plus the algorithm removals and renames below.
- **Dart API unchanged** — `KEM`, `Signature`, and `OQSRandom` are
  source-compatible; every breaking change is in *algorithm availability* or the
  bundled native library, not the class API.
- **SPHINCS+ removed (breaking)** — `Signature.create('SPHINCS+-…')` now returns
  `null`; migrate to **SLH-DSA** (FIPS 205) or **ML-DSA** (FIPS 204).
- **HQC renamed and enabled by default (breaking)** — `HQC-128`/`HQC-192`/`HQC-256`
  → `HQC-1`/`HQC-3`/`HQC-5`, updated to the 2025-08-22 spec.
- **FrodoKEM is now the salted variant (silent breaking)** — keys/ciphertexts are
  **not interoperable** with 0.15.0; the old ephemeral behavior moved to the new
  `eFrodoKEM-*` identifiers.
- **Now usable from standalone Dart** — the package dropped its Flutter SDK
  constraint (pure `dart:ffi`), so it works outside Flutter and shows both the
  Dart and Flutter badges on pub.dev.

#### Changed (Breaking)

- Upgraded bundled liboqs native library from 0.15.0 to 0.16.0.
- `FrodoKEM-640-AES`, `FrodoKEM-640-SHAKE`, `FrodoKEM-976-AES`,
  `FrodoKEM-976-SHAKE`, `FrodoKEM-1344-AES`, and `FrodoKEM-1344-SHAKE` now select
  the **salted** FrodoKEM variant instead of the ephemeral variant used in
  0.15.0. The identifiers are unchanged but keys and ciphertexts are **not
  interoperable** with 0.15.0. The previous ephemeral behavior is now available
  under the new `eFrodoKEM-*` identifiers (see Added). Prefer `eFrodoKEM-*` when
  each keypair encapsulates only a few shared secrets, and `FrodoKEM-*` (salted)
  for high-volume encapsulation.
- HQC identifiers were renamed `HQC-128`/`HQC-192`/`HQC-256` →
  `HQC-1`/`HQC-3`/`HQC-5`. HQC is now enabled by default and updated to the
  2025-08-22 specification. `KEM.create('HQC-128')` now returns `null`.

#### Changed

- `ML-DSA-44`/`ML-DSA-65`/`ML-DSA-87` are now backed by the portable
  `mldsa-native` implementation (with x86_64/aarch64 optimizations); identifiers
  and behavior are unchanged.
- `sntrup761` (NTRU Prime) now uses the public-domain OpenSSH implementation.
- Dropped the `flutter: ">=3.38.0"` SDK constraint. The package contains no
  Flutter imports (pure `dart:ffi`), so it is now usable from standalone Dart as
  well as Flutter, and pub.dev reports both the **Dart** and **Flutter** SDK
  badges (previously Flutter only). Verified with `pana`.
- `SECURITY.md` substantially expanded: secret lifetime and memory model (what
  the native/Dart layers guarantee and what garbage-collected memory cannot),
  timing-attack prevention, key-material handling, randomness, supply-chain
  integrity of the prebuilt native libraries (including the honest limits of
  same-release SHA256 verification), and a contributor security checklist.

#### Added

- Ephemeral FrodoKEM identifiers: `eFrodoKEM-640-AES`, `eFrodoKEM-640-SHAKE`,
  `eFrodoKEM-976-AES`, `eFrodoKEM-976-SHAKE`, `eFrodoKEM-1344-AES`, and
  `eFrodoKEM-1344-SHAKE`.
- HQC (`HQC-1`, `HQC-3`, `HQC-5`) is now enabled by default.
- Upstream runtime-detection API for stateful signature support (`OQS_SIG_STFL_*`).

#### Removed (Breaking)

- SPHINCS+ signature algorithms
  (`SPHINCS+-SHA2-128f-simple`, `-128s-simple`, `-192f-simple`, `-192s-simple`,
  `-256f-simple`, `-256s-simple`) were removed upstream in liboqs 0.16.0.
  `Signature.create('SPHINCS+-…')` now returns `null`. Migrate to **SLH-DSA**
  (FIPS 205, `SLH_DSA_PURE_*`) or **ML-DSA** (FIPS 204).
- Legacy HQC identifiers `HQC-128`/`HQC-192`/`HQC-256` (renamed; see Changed
  (Breaking)).

#### Fixed

- Build hook: the download cache key now includes the full version
  (`native_version` + `native_build`) and the full platform variant. Previously
  it keyed only on `os-arch`, which (1) let iOS device and simulator builds
  share `ios-arm64` on Apple-silicon hosts and poison each other's cache (dyld
  "incompatible platform" at runtime), and (2) omitted the version, so after a
  version bump a stale binary from the previous release could be reused instead
  of downloading the new one.

#### Security

- Build hook: SHA256 verification of downloaded native libraries is now
  **fail-closed**. Previously a missing or unreachable checksums file (e.g. a
  MITM blocking the checksums URL) was downgraded to a warning and the
  unverified binary was installed anyway. The build now aborts unless the new
  `LIBOQS_ALLOW_UNVERIFIED_DOWNLOAD=1` escape hatch is explicitly set.

Includes the following upstream liboqs 0.16.0 security fixes:

- Fixed uninitialized `encaps_derand` pointer dereference
  ([open-quantum-safe/liboqs#2460](https://github.com/open-quantum-safe/liboqs/pull/2460)).
- Fixed out-of-bounds read in XMSS/XMSS^MT signature verification
  ([open-quantum-safe/liboqs#2384](https://github.com/open-quantum-safe/liboqs/pull/2384)).
- Fixed integer underflow in CROSS `crypto_sign_open()`.
- Fixed incorrect array size when calling `secure_clean`.
- Added the `OQS_MEM_BLACK_BOX` optimization barrier hardening FrodoKEM
  `ct_select` constant-time protection
  ([open-quantum-safe/liboqs#2431](https://github.com/open-quantum-safe/liboqs/pull/2431)).

See the full [liboqs 0.16.0 release notes](https://github.com/open-quantum-safe/liboqs/releases/tag/0.16.0).

### For Contributors

#### Added

- `make check-targets` — guard that keeps the iOS/macOS deployment targets in the
  native build scripts internally consistent
  (`scripts/check_deployment_targets.dart`); now also enforced in CI (see
  Changed).
- `make release` — one-command scripted release (`scripts/release.dart`): checks
  you are on a clean, up-to-date `main`, verifies the native
  `liboqs-<fullVersion>` GitHub Release exists (fail-closed — the published
  build hook downloads it), bumps `pubspec.yaml`, finalizes the CHANGELOG
  `[Unreleased]` section including the bottom compare links, validates with a
  publish dry-run, then creates a signed commit + signed `vX.Y.Z` tag and
  pushes to trigger the pub.dev publish. Comes with a `release-package` skill
  guide and unit tests for the CHANGELOG finalization.
- `make update-changelog` — AI-drafted CHANGELOG entry for liboqs version bumps
  (`scripts/update_changelog.dart`, GitHub Models): classifies upstream changes
  by user visibility (algorithm additions/removals/renames and wire-format
  changes are breaking and user-visible; CI/docs/build-system churn is not).
  The liboqs update checker now includes such a draft `[Unreleased]` entry in
  its automated PRs (requires the `AI_MODELS_TOKEN` repository secret;
  non-fatal when absent).
- `make release-native` — deliberate, scripted release of the native libraries
  (`scripts/release_native.dart`): verifies a clean `main` exactly in sync with
  `origin/main` and that `liboqs-<fullVersion>` (tag and release) doesn't exist
  yet, then creates a signed `liboqs-<fullVersion>` tag and pushes it, which
  triggers the native build.
- `make setup-repo-protections` — applies the committed repository rulesets
  (`.github/rulesets/*.json`: protected release tags, protected `main`, signed
  commits, no branch deletion) and configures the `native-build` environment
  with a required reviewer via `gh` (`scripts/setup_repo_protections.dart`;
  runbook in `.github/rulesets/README.md`).

#### Changed

- Regenerated FFI bindings for liboqs 0.16.0.
- **CI hardening & reliability (Phase 4).** Workflows now run with a
  least-privilege `GITHUB_TOKEN` (workflow-level `contents: read`; only the
  release-publishing job opts up to `contents: write`). The native-library build
  workflow serializes via a `concurrency` group, so two quick `pubspec.yaml`
  pushes can no longer race to delete-and-recreate the same release tag. Windows
  runners install GNU Make from a pinned GitHub release (with retry + size check)
  via a `setup-make` composite action instead of Chocolatey. The
  deployment-target guard (`make check-targets`) runs in the CI quality checks
  alongside `analyze`/`format-check`. The publish workflow gained a dedicated
  package-validation (`publish-dry-run`) job that gates publishing. The liboqs
  update checker skips when an open update PR for the same version already
  exists, so scheduled runs no longer force-push over manual commits on that PR.
- **Tag-triggered native builds.** `build-liboqs.yml` now triggers on a
  `liboqs-<fullVersion>` tag push (created by `make release-native`) instead of
  every `pubspec.yaml` push to `main`: merging a version bump no longer builds
  or publishes anything by itself, the tag is validated against `pubspec.yaml`
  at the tagged commit, the GitHub Release is created on that same tag (the
  delete-then-recreate step is gone), and the release-publishing job is gated
  by the `native-build` environment (mirrors the pub.dev publish gate; inert
  until reviewers are configured).

#### Removed

- All platform-plugin scaffolding: the `ios/macos/liboqs.podspec` files, the
  `ios/Classes/LiboqsPlugin.swift` stub, the `android/` Gradle project
  (`build.gradle`, `settings.gradle`, `AndroidManifest.xml`), and the
  `linux/`/`windows/` `CMakeLists.txt` (plus stale generated app registrants).
  This is a plain Dart FFI package, not a Flutter plugin, so none of these files
  were ever consumed — a consuming app's `pod install` installs only
  `Flutter`/`FlutterMacOS`, and platform support is declared purely via the
  top-level `platforms:` key. Verified with `pana` (all five platform badges
  unchanged) and by rebuilding/running the iOS and macOS example. Native
  libraries continue to ship via Build Hooks.

## [1.2.1] - 2026-05-14

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

[Unreleased]: https://github.com/djx-y-z/liboqs_dart/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.2.1...v2.0.0
[1.2.1]: https://github.com/djx-y-z/liboqs_dart/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/djx-y-z/liboqs_dart/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/djx-y-z/liboqs_dart/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/djx-y-z/liboqs_dart/releases/tag/v1.0.0
