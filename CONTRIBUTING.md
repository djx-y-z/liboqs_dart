# Contributing to liboqs

Thank you for your interest in contributing to liboqs! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Coding Standards](#coding-standards)
- [Advanced Development](#advanced-development)
- [Security Considerations](#security-considerations)

## Code of Conduct

Please be respectful and considerate of others. We expect all contributors to:

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community

## Getting Started

### Prerequisites

- [Dart SDK](https://dart.dev/get-dart) (3.10.0+)
- Git
- **For building native libraries:** cmake, ninja

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/liboqs_dart.git
   cd liboqs_dart
   ```
3. Add upstream remote:
   ```bash
   git remote add upstream https://github.com/djx-y-z/liboqs_dart.git
   ```

## Development Setup

### Quick Setup (Recommended)

Run the setup command to install everything automatically:

```bash
make setup
```

This will:
1. Install FVM (Flutter Version Management)
2. Install the project's Flutter/Dart version (3.38.4)
3. Get all dependencies

### Verify Setup

```bash
# Show all available commands
make help

# Run tests to ensure everything works
make test
```

### Windows Users

On Windows, you need to install `make` first:
- Via Chocolatey: `choco install make`
- Via Scoop: `scoop install make`
- Or use Git Bash / WSL

Then run `make setup` as above.

### Project Structure

```
liboqs/
├── lib/                    # Main library code
│   ├── liboqs.dart         # Public API exports
│   └── src/
│       ├── bindings/       # FFI bindings (auto-generated)
│       ├── kem.dart        # Key Encapsulation Mechanisms
│       ├── signature.dart  # Digital Signatures
│       └── random.dart     # Random Number Generation
├── test/                   # Test files
├── example/                # Example application
├── bin/                    # Pre-built native libraries (server/CLI)
├── android/                # Android platform files
├── ios/                    # iOS platform files
├── macos/                  # macOS platform files
├── linux/                  # Linux platform files
├── windows/                # Windows platform files
├── scripts/                # Build scripts (use via Makefile!)
└── Makefile                # Entry point for all commands
```

## Making Changes

### Create a Branch

Create a branch for your changes:

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

### Types of Contributions

We welcome:

- **Bug fixes** - Fix issues in existing code
- **Documentation** - Improve docs, examples, comments
- **Tests** - Add or improve test coverage
- **Features** - New functionality (please discuss first)
- **Performance** - Optimizations with benchmarks

### Before You Start

For major changes:
1. Open an issue first to discuss the change
2. Wait for feedback from maintainers
3. This helps avoid wasted effort on changes that won't be merged

## Testing

### Running Tests

```bash
# Run all tests
make test

# Run specific test file
make test ARGS="test/kem_test.dart"

# Run with verbose output
make test ARGS="--reporter=expanded"
```

### Writing Tests

- Place tests in the `test/` directory
- Name test files with `_test.dart` suffix
- Test both success and error cases
- Include edge cases for cryptographic operations

Example test structure:

```dart
import 'package:test/test.dart';
import 'package:liboqs/liboqs.dart';

void main() {
  group('KEM', () {
    test('ML-KEM-768 key generation works', () {
      final kem = KEM.create('ML-KEM-768')!;
      final keyPair = kem.generateKeyPair();

      expect(keyPair.publicKey.length, equals(kem.publicKeyLength));
      expect(keyPair.secretKey.length, equals(kem.secretKeyLength));

      kem.dispose();
    });
  });
}
```

## Submitting Changes

### Commit Messages

Write clear, concise commit messages:

```
type: short description

Longer description if needed.

Fixes #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Adding or updating tests
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `perf`: Performance improvement
- `chore`: Maintenance tasks

### Pull Request Process

1. Update your branch with upstream:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. Push your branch:
   ```bash
   git push origin feature/your-feature-name
   ```

3. Create a Pull Request on GitHub

4. In your PR description:
   - Describe what the change does
   - Reference any related issues
   - Note any breaking changes
   - Include testing steps if applicable

5. Wait for review - maintainers will review and may request changes

### PR Checklist

Before submitting:

- [ ] Code follows the project's coding standards
- [ ] Tests pass locally (`make test`)
- [ ] Static analysis passes (`make analyze`)
- [ ] Code is formatted (`make format-check`)
- [ ] Documentation is updated if needed
- [ ] CHANGELOG.md is updated for user-facing changes
- [ ] Commit messages are clear and follow conventions

## Coding Standards

### Dart Style

Follow the [Effective Dart](https://dart.dev/effective-dart) guidelines:

```bash
# Format code
make format

# Check formatting without changes
make format-check

# Run static analysis
make analyze
```

- Use meaningful variable and function names
- Add documentation comments for public APIs
- Keep functions small and focused

### Documentation

- Document all public APIs with `///` comments
- Include examples in documentation where helpful
- Keep comments up to date with code changes

### FFI and Memory Safety

When working with FFI code:

- Always free allocated memory
- Use `try/finally` to ensure cleanup
- Zero out sensitive data before freeing
- Test for memory leaks

Example:

```dart
final ptr = calloc<Uint8>(size);
try {
  // Use ptr...
} finally {
  // Zero sensitive data
  for (var i = 0; i < size; i++) {
    ptr[i] = 0;
  }
  calloc.free(ptr);
}
```

## Advanced Development

### Makefile Commands Reference

All development tasks should be done via Makefile:

| Command | Description |
|---------|-------------|
| `make setup` | Install FVM + Flutter + dependencies |
| `make help` | Show all available commands |
| `make test` | Run all tests |
| `make analyze` | Run static analysis |
| `make format` | Format code |
| `make format-check` | Check formatting |
| `make build ARGS="<platform>"` | Build native libraries |
| `make regen` | Regenerate FFI bindings |
| `make check` | Check for liboqs updates |
| `make get` | Get dependencies |
| `make clean` | Clean build artifacts |
| `make version` | Show liboqs version |

### Regenerating FFI Bindings

When the liboqs version changes, you may need to regenerate Dart FFI bindings:

```bash
# Option 1: Automatic update (recommended)
make check ARGS="--update"

# Option 2: Manual update
# Edit pubspec.yaml - update liboqs.native_version to new version

# Regenerate bindings (downloads liboqs, builds headers, runs ffigen)
make regen

# Test the new bindings
make test
```

**When to regenerate:**
- After updating `liboqs.native_version` in pubspec.yaml
- If liboqs adds new functions you want to use
- If struct layouts change in a new version

**Requirements:**
- cmake
- ninja (optional, faster builds)

### Building Native Libraries

Native libraries are normally built automatically by CI when `liboqs.native_version` in pubspec.yaml changes.
However, you can build them locally for testing or development.

```bash
# List available platforms
make build ARGS="list"

# Build for your current platform
make build ARGS="macos"
make build ARGS="linux"
make build ARGS="windows"

# Build with specific options
make build ARGS="macos --arch arm64"
make build ARGS="ios --target simulator"
make build ARGS="android --abi arm64-v8a"

# Build all available platforms
make build ARGS="all"
```

**Platform requirements:**

| Platform | Build OS | Requirements |
|----------|----------|--------------|
| Linux | Linux | cmake, ninja, gcc |
| macOS | macOS | cmake, ninja, Xcode CLI |
| iOS | macOS | cmake, ninja, Xcode |
| Android | Linux/macOS | cmake, ninja, Android NDK |
| Windows | Windows | cmake, ninja, Visual Studio |

For more details, see `scripts/README.md`.

### Third-Party Notices

The native library is compiled from the liboqs sources, which vendor code under
licences other than liboqs' own MIT. `THIRD_PARTY_NOTICES.txt` records what that
code is and reproduces the notices those licences require. It is generated, so
never edit it by hand:

```bash
make third-party-notices          # regenerate (clones liboqs at the pinned version)
make verify-third-party-notices   # verify the committed copy matches
```

The verify step runs in CI, before the native build, and in both release
preflights, and compares byte for byte. If it fails, the message names the first
differing line; regenerate and commit the result.

Two things make this more than a directory walk, and are worth knowing before you
change the generator:

- **Most sources have no licence file of their own.** 2532 of the 5957 sources
  under `src/` — 43% — have no LICENSE anywhere between them and the repository
  root, so each
  source is resolved through its own SPDX tag first, then the nearest licence
  file, then `docs/algorithms/<class>/<family>.yml`, then an explicit override.
  A source matched by none of the four is a hard error — that is deliberate, and
  it is what makes a liboqs upgrade that vendors a new licence stop and ask for
  a person.
- **Upstream data is not uniform.** Two files carry mangled SPDX tags, one file
  inside the Keccak tree is under a licence with no SPDX identifier at all, and
  two algorithms state their licence only in `docs/algorithms/`. The generator
  encodes each of these with the evidence for it; see
  `scripts/src/third_party_notices.dart`.

### Pins Dependabot Cannot See

Two versions in CI are pinned by hand, because they are not declared in any
manifest Dependabot scans. Both need a deliberate bump and a look at what it
changes:

- **`fvm-version` in `.github/actions/setup-fvm/action.yml`** — installed with
  `dart pub global activate`, which is not a manifest. The action hardcodes where
  FVM stores SDKs, and a guard step fails the job if they land elsewhere, so after
  a bump confirm the new FVM still resolves its cache to `$FVM_CACHE_PATH/versions`.
- **`ACTIONLINT_VERSION` in the `Makefile`** — pinned by version *and* SHA256,
  because GitHub release assets are mutable. Take the new checksums from the
  `actionlint_<version>_checksums.txt` asset of the release you are moving to.

## Security Considerations

This is a **cryptographic library**. Security is paramount.

### Reporting Security Issues

**Do not open public issues for security vulnerabilities.**

Instead, report security issues privately:
- Email: [create a security advisory on GitHub]
- Use GitHub's private vulnerability reporting

### Security Review Checklist

For cryptographic code changes:

- [ ] No hardcoded keys or secrets
- [ ] Sensitive data is zeroed after use
- [ ] Memory is properly freed
- [ ] No timing side-channels introduced
- [ ] Random number generation uses secure source
- [ ] Error handling doesn't leak sensitive information

### Upstream Changes

This library wraps [liboqs](https://github.com/open-quantum-safe/liboqs). When updating liboqs:

1. Review the liboqs changelog for security fixes
2. Test all algorithms after update
3. Update `liboqs.native_version` in pubspec.yaml (or use `make check ARGS="--update"`)
4. Regenerate FFI bindings with `make regen`

## Questions?

- Open an issue for general questions
- Check existing issues before creating new ones
- Be patient - maintainers are volunteers

Thank you for contributing!
