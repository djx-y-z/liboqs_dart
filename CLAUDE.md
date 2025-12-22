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
| Run analysis | `make analyze` |
| Strict analysis | `make analyze ARGS="--fatal-infos"` |
| Format code | `make format` |
| Regenerate FFI bindings | `make regen` |
| Check for updates | `make check` |
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
make build ARGS="ios"                      # Build for iOS (xcframework)
make build ARGS="ios --target simulator"   # Build for iOS simulator only
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

### Quality Assurance
```bash
make test                                # Run all tests
make test ARGS="test/kem_test.dart"      # Run specific test file
make analyze                             # Run static analysis
make analyze ARGS="--fatal-infos"        # Strict analysis
make format                              # Format Dart code
make format-check                        # Check formatting without changes
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
├── ios/Frameworks/                 # iOS xcframework
├── macos/Libraries/                # macOS Flutter library
├── scripts/                        # Build scripts (use via Makefile!)
├── test/                           # Tests
├── Makefile                        # Entry point for all commands
├── LIBOQS_VERSION                  # Current liboqs version
└── .github/workflows/              # CI/CD workflows
```

## Common Development Tasks

### Update liboqs Version

```bash
# 1. Update version file
echo "0.16.0" > LIBOQS_VERSION

# 2. Regenerate FFI bindings
make regen

# 3. Run tests
make test

# 4. Commit and push (CI will build native libraries)
git add LIBOQS_VERSION lib/src/bindings/
git commit -m "Update liboqs to 0.16.0"
git push
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
| iOS | XCFramework | `ios/Frameworks/liboqs.xcframework` |
| Android | arm64-v8a, armeabi-v7a, x86_64 | `android/src/main/jniLibs/` |

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
   - Document Dart GC limitations for `Uint8List` containing secrets

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

## Publishing Checklist

```bash
# 1. Run quality checks
make analyze
make test
make format-check

# 2. Update version in pubspec.yaml
# 3. Update CHANGELOG.md

# 4. Dry run
make publish-dry-run

# 5. Publish
make publish
```
