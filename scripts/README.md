# liboqs Build Scripts

Cross-platform Dart scripts for building liboqs native libraries.
These scripts work on Windows, macOS, and Linux.

> **Recommended:** Use `make build` instead of calling scripts directly.
> The Makefile automatically handles Build Hook skip markers to avoid
> chicken-and-egg problems during native library compilation.
> See the root [CLAUDE.md](../CLAUDE.md) for details.

## Prerequisites

- [FVM](https://fvm.app/) (Flutter Version Management)
- cmake
- ninja

## Quick Start

**Using Makefile (recommended):**
```bash
# Install FVM and project Flutter version
make setup

# Build for your current platform
make build ARGS="macos"
make build ARGS="linux"
make build ARGS="windows"

# List available platforms
make build ARGS="list"
```

**Direct script invocation (advanced):**
```bash
# Note: Direct invocation doesn't skip Build Hooks automatically.
# Use `touch .skip_liboqs_hook` before and `rm .skip_liboqs_hook` after.
fvm dart run scripts/build.dart macos
fvm dart run scripts/build.dart linux
fvm dart run scripts/build.dart windows
```

## Scripts

| Script | Description |
|--------|-------------|
| `build.dart` | Build native libraries for any platform |
| `regenerate_bindings.dart` | Regenerate Dart FFI bindings |
| `check_updates.dart` | Check for liboqs updates and update files |
| `combine_artifacts.dart` | Combine CI artifacts (used by GitHub Actions) |
| `update_changelog.dart` | AI-generated CHANGELOG entry for a liboqs bump (`make update-changelog`) |
| `release_native.dart` | Release the native libraries: signed tag `liboqs-<fullVersion>`, push — triggers the CI build (`make release-native`) |
| `release.dart` | Release the Dart package: bump, finalize CHANGELOG, tag, push (`make release`) |
| `setup_repo_protections.dart` | Apply `.github/rulesets/*.json` + the `native-build` environment to GitHub (`make setup-repo-protections`) |
| `generate_third_party_notices.dart` | Generate or verify `THIRD_PARTY_NOTICES.txt` from the liboqs sources (`make third-party-notices`, `make verify-third-party-notices`) |
| `check_action_pins.dart` | Resolve every third-party `uses:` in `.github` against the GitHub API (`make check-action-pins`) |

## Build Commands

### Linux

```bash
fvm dart run scripts/build.dart linux
```

Output: `bin/linux/liboqs.so`

Requirements: cmake, ninja, gcc/g++

### macOS

```bash
# Universal Binary (default)
fvm dart run scripts/build.dart macos

# Specific architecture
fvm dart run scripts/build.dart macos --arch arm64
fvm dart run scripts/build.dart macos --arch x86_64
```

Output:
- `bin/macos/liboqs.dylib`
- `macos/Libraries/liboqs.dylib` (Flutter plugin)

Requirements: cmake, ninja, Xcode Command Line Tools

### iOS

```bash
# XCFramework with all targets (default)
fvm dart run scripts/build.dart ios

# Specific target
fvm dart run scripts/build.dart ios --target device
fvm dart run scripts/build.dart ios --target simulator-arm64
fvm dart run scripts/build.dart ios --target simulator-x86_64
```

Output: `ios/Frameworks/liboqs.xcframework/`

Requirements: macOS, cmake, ninja, Xcode

### Android

```bash
# All ABIs (default)
fvm dart run scripts/build.dart android

# Specific ABI
fvm dart run scripts/build.dart android --abi arm64-v8a
fvm dart run scripts/build.dart android --abi armeabi-v7a
fvm dart run scripts/build.dart android --abi x86_64
```

Output: `android/src/main/jniLibs/{abi}/liboqs.so`

Requirements: cmake, ninja, Android NDK

**Android NDK Setup:**
```bash
# Option 1: Environment variable
export ANDROID_NDK_HOME=/path/to/ndk/26.3.11579264

# Option 2: Install via Android Studio
# SDK Manager → SDK Tools → NDK (Side by side)
```

### Windows

```bash
fvm dart run scripts/build.dart windows
```

Output: `bin/windows/oqs.dll`

Requirements: cmake, ninja, Visual Studio with C++ workload

**Note:** Run from "Developer PowerShell for VS" or after running `vcvars64.bat`.

## Checking for Updates

Check for new liboqs releases and optionally update local files:

```bash
# Just check for updates
fvm dart run scripts/check_updates.dart

# Check and update pubspec.yaml and CHANGELOG.md
fvm dart run scripts/check_updates.dart --update

# Update to specific version
fvm dart run scripts/check_updates.dart --update --version 0.16.0

# Force major version bump
fvm dart run scripts/check_updates.dart --update --bump major

# Update without changelog (for CI - AI generates changelog separately)
fvm dart run scripts/check_updates.dart --update --no-changelog

# Output JSON for CI integration
fvm dart run scripts/check_updates.dart --json
```

This script is used by both local development and the `check-liboqs-updates.yml` workflow.
The workflow uses `--no-changelog` flag and generates AI-enhanced changelog separately.

## Regenerating FFI Bindings

When updating liboqs version:

```bash
# Option 1: Automatic update (recommended)
make check ARGS="--update"

# Option 2: Manual update
# Edit pubspec.yaml - update liboqs.native_version to new version

# Regenerate bindings
make regen

# Test
make test
```

## Platform Requirements Summary

| Platform | Build OS | Requirements |
|----------|----------|--------------|
| Linux | Linux | cmake, ninja, gcc |
| macOS | macOS | cmake, ninja, Xcode CLI |
| iOS | macOS | cmake, ninja, Xcode |
| Android | Linux/macOS | cmake, ninja, Android NDK |
| Windows | Windows | cmake, ninja, Visual Studio |

## CI Integration

These scripts are used by GitHub Actions workflow (`.github/workflows/build-liboqs.yml`),
which triggers on a `liboqs-<fullVersion>` tag push (`make release-native`).
The workflow:
1. Validates the tag against `pubspec.yaml` (`check_release.dart`)
2. Builds each platform on appropriate runners
3. Uploads artifacts
4. Publishes a GitHub Release with the archives on the same tag

## Why Dart Scripts?

Previous shell scripts had cross-platform issues:
- `.sh` scripts don't work natively on Windows
- `.ps1` scripts don't work on Linux/macOS

Dart scripts solve this:
- FVM provides consistent Dart SDK version
- Same script works on all platforms
- Easier to maintain (one language)
- Better error handling and debugging
