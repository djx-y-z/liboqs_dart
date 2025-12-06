# OQS Dart - Fork Information

This is a fork of [oqs](https://pub.dev/packages/oqs) package with pre-built native libraries.

## Upstream Repository

- **Original**: https://github.com/bardiakz/oqs
- **pub.dev**: https://pub.dev/packages/oqs
- **Current version**: 2.2.0

## Why Fork?

1. **Security** - Control over dependencies, audit before merge
2. **Pre-built binaries** - Native libraries built via GitHub Actions
3. **Consistency** - Same liboqs version across all platforms
4. **Supply chain** - No reliance on external package updates

## Native Library: liboqs

- **Version**: 0.15.0
- **Algorithm**: ML-DSA-65 (NIST FIPS 204)
- **Build**: Minimal build with only ML-DSA-65 enabled

### Platforms

| Platform | Architecture | File | Location |
|----------|--------------|------|----------|
| Linux | x86_64 | `liboqs.so` | `bin/linux/` |
| macOS | arm64 | `liboqs.dylib` | `bin/macos/` |
| macOS | x86_64 | `liboqs.dylib` | `bin/macos-x86_64/` |
| iOS | arm64 | `liboqs.dylib` | `bin/ios/` |
| Android | arm64-v8a | `liboqs.so` | `bin/android/arm64-v8a/` |
| Android | armeabi-v7a | `liboqs.so` | `bin/android/armeabi-v7a/` |
| Android | x86_64 | `liboqs.so` | `bin/android/x86_64/` |
| Windows | x86_64 | `oqs.dll` | `bin/windows/` |

## Syncing with Upstream

### Add upstream remote (one-time)

```bash
cd flutter/packages/oqs_dart
git remote add upstream https://github.com/bardiakz/oqs.git
```

### Check for updates

```bash
git fetch upstream
git log HEAD..upstream/main --oneline
```

### Review and merge changes

```bash
# View diff
git diff HEAD upstream/main

# Merge after review
git merge upstream/main

# Resolve conflicts if any
# Rebuild native libraries via GitHub Actions
# Push to origin
git push origin main
```

## Rebuilding Native Libraries

Native libraries are built automatically via GitHub Actions when:
- Push to `main` with changes to `.github/workflows/build-liboqs.yml`
- New tag matching `v*` or `liboqs-*`
- Manual workflow dispatch

### Manual trigger

1. Go to Actions tab in GitHub
2. Select "Build liboqs Native Libraries"
3. Click "Run workflow"
4. Optionally specify liboqs version (default: 0.15.0)

### Local build (for testing)

```bash
# macOS arm64
cd /tmp
git clone --depth 1 --branch 0.15.0 https://github.com/open-quantum-safe/liboqs.git
cd liboqs && mkdir build && cd build
cmake .. -DBUILD_SHARED_LIBS=ON -DOQS_BUILD_ONLY_LIB=ON \
  -DOQS_MINIMAL_BUILD="OQS_ENABLE_SIG_ml_dsa_65" -G Ninja
ninja
# Copy lib/liboqs.dylib to bin/macos/
```

## Version History

| Date | oqs version | liboqs version | Notes |
|------|-------------|----------------|-------|
| 2024-12-06 | 2.2.0 | 0.15.0 | Initial fork |
