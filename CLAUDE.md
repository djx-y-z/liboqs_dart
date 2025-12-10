# liboqs - Claude Code Configuration

## Important Rules

**ALWAYS use Makefile commands.** Never call scripts directly via `fvm dart run scripts/...`. The Makefile is the single entry point for all operations.

```bash
# Correct
make build macos
make test
make regen

# Wrong - never do this
fvm dart run scripts/build.dart macos
```

## Quick Reference

| Task | Command |
|------|---------|
| Initial setup | `make setup` |
| Show all commands | `make help` |
| Build native library | `make build <platform>` |
| Run tests | `make test` |
| Run analysis | `make analyze` |
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
make build <platform> [options]   # Build native libraries
make build macos                  # Build for macOS (universal)
make build macos --arch arm64     # Build for specific architecture
make build ios                    # Build for iOS (xcframework)
make build ios --target simulator # Build for iOS simulator only
make build android                # Build for Android (all ABIs)
make build android --abi arm64-v8a
make build linux                  # Build for Linux
make build windows                # Build for Windows
make build all                    # Build all platforms
make build list                   # List available platforms
```

### Development
```bash
make regen                        # Regenerate Dart FFI bindings
make check                        # Check for liboqs updates
make check --update               # Check and apply updates
make check --json                 # Output JSON (for CI)
make combine                      # Combine CI artifacts
```

### Quality Assurance
```bash
make test                         # Run all tests
make test test/kem_test.dart      # Run specific test file
make analyze                      # Run static analysis
make analyze --fatal-infos        # Strict analysis
make format                       # Format Dart code
make format-check                 # Check formatting without changes
```

### Utilities
```bash
make get                          # Get dependencies
make clean                        # Clean build artifacts
make version                      # Show current liboqs version
make help                         # Show all available commands
```

## Project Overview

This is a **security-audited fork** of [oqs](https://pub.dev/packages/oqs) - Dart FFI bindings for liboqs post-quantum cryptography library.

### Key Features
- Pre-built native libraries for all platforms
- Automated security updates via GitHub Actions
- Cross-platform build scripts

### Upstream Repositories
- **Original package**: https://pub.dev/packages/oqs
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
make check --update

# Check with specific version
make check --update --version 0.16.0
```

### Build Native Libraries Locally

```bash
# List available platforms
make build list

# Build for current platform
make build macos
make build linux
make build windows

# Build with options
make build macos --arch arm64
make build ios --target device
make build android --abi arm64-v8a
```

### Run Tests

```bash
# All tests
make test

# Specific test file
make test test/kem_test.dart

# With verbose output
make test --reporter=expanded
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

### Supply Chain Security
- All native libraries are built from source in GitHub Actions
- Pin to specific liboqs releases (no `main` branch builds)
- Review upstream changes before merging

### Code Review Checklist
1. No hardcoded keys or secrets
2. Memory properly freed after use
3. Sensitive data zeroed before freeing
4. No timing side-channels

## FVM (Flutter Version Management)

This project uses FVM for consistent Flutter/Dart versions.

**Version:** Flutter 3.32.8 (Dart SDK 3.8.1)

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
dart pub publish --dry-run

# 5. Publish
dart pub publish
```
