# liboqs - Claude Code Configuration

## Important Rules

**ALWAYS use Makefile commands.** Never call scripts directly via `fvm dart run scripts/...`. The Makefile is the single entry point for all operations.

```bash
# Correct - pass arguments via ARGS variable
make build ARGS="macos"
make build ARGS="macos --arch arm64"
make test
make analyze ARGS="--fatal-infos"

# Wrong - never do this
fvm dart run scripts/build.dart macos
make build macos --arch arm64  # make interprets --arch as its own flag!
```

## Quick Reference

| Task | Command |
|------|---------|
| Initial setup | `make setup` |
| Show all commands | `make help` |
| Build native library | `make build ARGS="<platform>"` |
| Run tests | `make test` |
| Run tests with coverage | `make coverage` |
| Run analysis | `make analyze` |
| Strict analysis | `make analyze ARGS="--fatal-infos"` |
| Format code | `make format` |
| Check deployment targets (iOS/macOS) | `make check-targets` |
| Generate documentation | `make doc` |
| Regenerate FFI bindings | `make regen` |
| Check for updates | `make check` |
| Update CHANGELOG for a liboqs bump (AI) | `make update-changelog ARGS="--version 0.17.0 --from 0.16.0"` |
| Release the native libraries (tag-trigger CI build) | `make release-native` |
| Release the package | `make release ARGS="--version X.Y.Z"` |
| Apply repo protections (one-time, gh admin) | `make setup-repo-protections` |
| Get dependencies | `make get` |
| Show liboqs version | `make version` |

## Available Makefile Commands

### Setup
```bash
make setup                        # Install FVM + Flutter + dependencies (run once)
```

### Build
```bash
make build ARGS="<platform> [options]"     # Build native libraries
make build ARGS="macos"                    # Build for macOS (universal)
make build ARGS="macos --arch arm64"       # Build for specific architecture
make build ARGS="ios"                      # Build for iOS (device + simulator dylibs)
make build ARGS="ios --target simulator-arm64"   # Build for a single iOS target
make build ARGS="android"                  # Build for Android (all ABIs)
make build ARGS="android --abi arm64-v8a"
make build ARGS="linux"                    # Build for Linux
make build ARGS="windows"                  # Build for Windows
make build ARGS="all"                      # Build all platforms
make build ARGS="list"                     # List available platforms
```

**Note:** `make build` automatically creates a `.skip_liboqs_hook` marker file to prevent Build Hooks from downloading libraries during the build process (avoids chicken-and-egg problem). The marker is automatically removed after the build completes.

### Development
```bash
make regen                              # Regenerate Dart FFI bindings
make check                              # Check for liboqs updates
make check ARGS="--update"              # Check and apply updates
make check ARGS="--json"                # Output JSON (for CI)
make combine                            # Combine CI artifacts
```

**Note:** `make regen` also creates a `.skip_liboqs_hook` marker file to prevent Build Hooks from running during regeneration. The marker is automatically removed after the command completes.

### Quality Assurance
```bash
make test                                # Run all tests
make test ARGS="test/kem_test.dart"      # Run specific test file
make coverage                            # Run tests with coverage report
make analyze                             # Run static analysis
make analyze ARGS="--fatal-infos"        # Strict analysis
make format                              # Format Dart code
make format-check                        # Check formatting without changes
make check-targets                       # Check iOS/macOS deployment target consistency
make check-targets ARGS="--update"       # Fix deployment target drift in-place
```

### Utilities
```bash
make get                          # Get dependencies
make clean                        # Clean build artifacts
make version                      # Show current liboqs version
make help                         # Show all available commands
```

## Project Overview

Dart FFI bindings for liboqs post-quantum cryptography library.

### Key Features
- Pre-built native libraries for all platforms
- Automated security updates via GitHub Actions
- Cross-platform build scripts

### Upstream Repository
- **liboqs**: https://github.com/open-quantum-safe/liboqs

## Project Structure

```
liboqs/
├── lib/                            # Dart library code
│   └── src/bindings/
│       └── liboqs_bindings.dart    # Auto-generated FFI bindings
├── bin/                            # Pre-built server/CLI libraries
│   ├── linux/liboqs.so
│   ├── macos/liboqs.dylib
│   └── windows/oqs.dll
├── android/src/main/jniLibs/       # Android libraries
├── ios/Libraries/                  # iOS per-target dylibs (local builds)
├── macos/Libraries/                # macOS Flutter library
├── scripts/                        # Build scripts (use via Makefile!)
├── test/                           # Tests
├── Makefile                        # Entry point for all commands
├── pubspec.yaml                    # Package config + liboqs.native_version
└── .github/workflows/              # CI/CD workflows
```

## Common Development Tasks

### Update liboqs Version

Native library version is stored in `pubspec.yaml` under `liboqs.native_version`.

```bash
# Option 1: Automatic update
make check ARGS="--update"

# Option 2: Manual update
# 1. Edit pubspec.yaml - update liboqs.native_version to new version
# 2. Regenerate FFI bindings
make regen

# 3. Run tests
make test

# 4. Commit and push (PR -> main; merging does NOT build anything by itself)
git add pubspec.yaml lib/src/bindings/
git commit -m "Update liboqs to 0.16.0"
git push

# 5. After the bump merges to main: trigger the native build from an
#    up-to-date main (signed tag liboqs-<fullVersion> -> build-liboqs.yml)
make release-native
```

### Check for liboqs Updates

```bash
# Just check (no changes)
make check

# Check and apply updates
make check ARGS="--update"

# Check with specific version
make check ARGS="--update --version 0.16.0"
```

### Build Native Libraries Locally

```bash
# List available platforms
make build ARGS="list"

# Build for current platform
make build ARGS="macos"
make build ARGS="linux"
make build ARGS="windows"

# Build with options
make build ARGS="macos --arch arm64"
make build ARGS="ios --target device"
make build ARGS="android --abi arm64-v8a"
```

### Run Tests

```bash
# All tests
make test

# Specific test file
make test ARGS="test/kem_test.dart"

# With verbose output
make test ARGS="--reporter=expanded"
```

## Supported Platforms

| Platform | Architecture | Location |
|----------|--------------|----------|
| Linux | x86_64 | `bin/linux/liboqs.so` |
| macOS | Universal (arm64 + x86_64) | `bin/macos/liboqs.dylib` |
| Windows | x86_64 | `bin/windows/oqs.dll` |
| iOS | device arm64; simulator arm64, x86_64 | `ios/Libraries/<target>-<arch>/liboqs.dylib` |
| Android | arm64-v8a, armeabi-v7a, x86_64 | `android/src/main/jniLibs/` |

**Native delivery — no platform folders:** the package is a plain Dart FFI package.
It is **not** a Flutter plugin (no `flutter: plugin:` section) and ships **no**
platform scaffolding — no `ios/macos` podspecs, no `android/` Gradle project, no
`linux/windows` CMake files. Native libraries are delivered exclusively through the
Build Hook (`hook/build.dart`) as native assets; on iOS/macOS Flutter converts the
`.dylib` to a framework and embeds/signs it, on Android/Linux/Windows it bundles the
`.so`/`.dll`. Platform support is declared purely via the top-level `platforms:` key
in `pubspec.yaml` (verified with `pana`: all five platform tags plus `sdk:dart` +
`sdk:flutter`). A fresh `pod install` in a consuming app installs only
`Flutter`/`FlutterMacOS`. The `ios/Libraries`, `macos/Libraries`, and
`android/src/main/jniLibs` directories are **local** `make build` outputs only
(git-ignored; consumers download prebuilt libs via the hook).

## Security Considerations

> **Important:** See [SECURITY.md](SECURITY.md) for full security policy and best practices.

### Supply Chain Security
- All native libraries are built from source in GitHub Actions
- Pin to specific liboqs releases (no `main` branch builds)
- Review upstream changes before merging

### Code Review Checklist
1. No hardcoded keys or secrets
2. Memory properly freed after use
3. Sensitive data zeroed before freeing
4. No timing side-channels

### Security Rules for New Code

When adding new cryptographic functionality:

1. **Memory Management:**
   - Use `LibOQSUtils.secureFreePointer(ptr, length)` for secret data (uses `OQS_MEM_secure_free`)
   - Use `LibOQSUtils.freePointer(ptr)` only for non-sensitive data (public keys, ciphertext)
   - Always free memory in `finally` blocks

2. **Key/Secret Handling:**
   - Add `clearSecrets()` method to any class holding secret keys or shared secrets
   - Add `Finalizer` to auto-zero secrets on GC (defense-in-depth):
     ```dart
     final Finalizer<Uint8List> _secretDataFinalizer = Finalizer((data) {
       data.fillRange(0, data.length, 0);
     });
     // In constructor: _secretDataFinalizer.attach(this, secretKey, detach: this);
     ```
   - Document with `/// **Security Warning:**` if methods expose secrets
   - Provide safe alternatives (e.g., `publicKeyBase64` instead of `toStrings()`)

3. **Comparisons:**
   - Use `LibOQSUtils.constantTimeEquals()` for comparing secrets (prevents timing attacks)
   - Never use `==` or loop-based comparison for secret data

4. **Function Pointers:**
   - Validate native function pointers before calling `asFunction()`
   - Example: `if (_ptr.ref.func == nullptr) throw LibOQSException(...)`

5. **dispose() Pattern:**
   - Order: `free() -> detach() -> flag = true`
   - This prevents memory leaks if exception occurs during cleanup

6. **Documentation:**
   - Add `/// **Security Warning:**` to methods that expose secrets
   - Document that Finalizers provide automatic cleanup, but explicit `clearSecrets()` is recommended

## FVM (Flutter Version Management)

This project uses FVM for consistent Flutter/Dart versions.

**Version:** Flutter 3.38.4 (Dart SDK 3.10.0)

FVM is automatically installed by `make setup`.

## Windows Users

On Windows, install `make` first:
- Chocolatey: `choco install make`
- Scoop: `scoop install make`
- Or use Git Bash / WSL

## Changelog Format

Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format:

```markdown
## X.Y.Z

### Added
- New features

### Changed
- Changes in existing functionality

### Fixed
- Bug fixes

### Security
- Security-related changes
```

## Publishing

Releases go through `make release` (see the `release-package` skill in
`.claude/skills/release-package/SKILL.md` for the full guide):

```bash
# Preconditions: clean up-to-date main, native release liboqs-<fullVersion>
# already built by CI (tag pushed via `make release-native` after the version
# bump merged), SSH signing key loaded (ssh-add -l).
make release ARGS="--version X.Y.Z"
```

It bumps `pubspec.yaml`, finalizes the CHANGELOG (`[Unreleased]` → `[X.Y.Z]`),
validates with `make publish-dry-run`, creates a signed commit + signed tag
`vX.Y.Z`, and pushes — the tag triggers `publish.yml`, which publishes to
pub.dev via OIDC. Never run `dart pub publish` manually (`make publish` is
CI-only and blocked locally).
