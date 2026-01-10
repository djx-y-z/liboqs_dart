---
name: build-native
description: Build liboqs native libraries for different platforms. Use when user asks about building, compiling, or creating native libraries for iOS, Android, macOS, Linux, or Windows.
---

# Build Native Libraries

Help with building liboqs native libraries for all supported platforms.

## Golden Rule

**ALWAYS use Makefile commands. Never call scripts directly.**

```bash
# CORRECT
make build ARGS="macos"

# WRONG - never do this
fvm dart run scripts/build.dart macos
```

## Quick Reference

| Platform | Command | Output |
|----------|---------|--------|
| macOS | `make build ARGS="macos"` | `bin/macos/liboqs.dylib` |
| Linux | `make build ARGS="linux"` | `bin/linux/liboqs.so` |
| Windows | `make build ARGS="windows"` | `bin/windows/oqs.dll` |
| iOS | `make build ARGS="ios"` | `ios/Frameworks/liboqs.xcframework/` |
| Android | `make build ARGS="android"` | `android/src/main/jniLibs/` |
| All | `make build ARGS="all"` | All platforms |
| List | `make build ARGS="list"` | Show available platforms |

## Platform-Specific Options

### macOS

```bash
# Universal binary (arm64 + x86_64) - default
make build ARGS="macos"

# Specific architecture
make build ARGS="macos --arch arm64"
make build ARGS="macos --arch x86_64"
```

### iOS

```bash
# Full XCFramework (device + simulators) - default
make build ARGS="ios"

# Specific targets
make build ARGS="ios --target device"
make build ARGS="ios --target simulator"
make build ARGS="ios --target simulator-arm64"
make build ARGS="ios --target simulator-x86_64"
```

### Android

```bash
# All ABIs - default
make build ARGS="android"

# Specific ABI
make build ARGS="android --abi arm64-v8a"
make build ARGS="android --abi armeabi-v7a"
make build ARGS="android --abi x86_64"
```

**Android NDK Setup:**
```bash
export ANDROID_NDK_HOME=/path/to/ndk/26.3.11579264
# Or install via Android Studio SDK Manager
```

### Windows

```bash
make build ARGS="windows"
```

**Requirements:** Run from "Developer PowerShell for VS" or after `vcvars64.bat`

## Prerequisites

| Platform | Requirements |
|----------|--------------|
| All | cmake, ninja, FVM |
| Linux | gcc/g++ |
| macOS | Xcode Command Line Tools |
| iOS | Xcode (full) |
| Android | Android NDK |
| Windows | Visual Studio with C++ |

## Troubleshooting

### "cmake not found"
```bash
# macOS
brew install cmake ninja

# Linux
sudo apt install cmake ninja-build

# Windows
choco install cmake ninja
```

### "NDK not found" (Android)
```bash
# Check current NDK
echo $ANDROID_NDK_HOME

# Common paths
export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.3.11579264
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/26.3.11579264
```

### Build fails on Windows
- Ensure you're in "Developer PowerShell for VS"
- Or run `vcvars64.bat` first

## Output Locations

| Platform | Library Location |
|----------|------------------|
| Linux (CLI) | `bin/linux/liboqs.so` |
| macOS (CLI) | `bin/macos/liboqs.dylib` |
| Windows (CLI) | `bin/windows/oqs.dll` |
| macOS (Flutter) | `macos/Libraries/liboqs.dylib` |
| iOS (Flutter) | `ios/Frameworks/liboqs.xcframework/` |
| Android (Flutter) | `android/src/main/jniLibs/{abi}/liboqs.so` |
