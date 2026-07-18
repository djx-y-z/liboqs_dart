---
name: update-liboqs
description: Update liboqs native library version. Use when checking for updates, upgrading liboqs, bumping version, or updating native dependencies.
---

# Update liboqs Version

Guide for updating the liboqs native library version in this project.

## Quick Update (Automatic)

```bash
# Check for updates
make check

# Check and apply updates automatically
make check ARGS="--update"
```

This will:
1. Check GitHub for latest liboqs release
2. Update `pubspec.yaml` with new `liboqs.native_version`
3. Update CHANGELOG.md with new entry

## Manual Update Process

### Step 1: Check Current Version

```bash
make version
```

Or check `pubspec.yaml`:
```yaml
liboqs:
  native_version: "0.12.0"  # Current version
```

### Step 2: Update Version

Edit `pubspec.yaml`:
```yaml
liboqs:
  native_version: "0.13.0"  # New version
```

### Step 3: Regenerate FFI Bindings

```bash
make regen
```

This downloads the new liboqs headers and regenerates `lib/src/bindings/liboqs_bindings.dart`.

### Step 4: Run Tests

```bash
make test
```

### Step 5: Commit Changes

```bash
git add pubspec.yaml lib/src/bindings/ CHANGELOG.md
git commit -m "Update liboqs to 0.13.0"
git push
```

Merging to `main` does NOT build anything by itself. After the merge, from an
up-to-date `main`, trigger the native build with:

```bash
make release-native
```

It creates and pushes the signed tag `liboqs-<native_version>-<native_build>`,
which triggers `build-liboqs.yml` to build all platforms and publish the
GitHub Release.

## Check Options

```bash
# Just check (no changes)
make check

# Check and update
make check ARGS="--update"

# Update to specific version
make check ARGS="--update --version 0.13.0"

# Force version bump type
make check ARGS="--update --bump major"
make check ARGS="--update --bump minor"
make check ARGS="--update --bump patch"

# Skip changelog (CI uses this)
make check ARGS="--update --no-changelog"

# JSON output for CI
make check ARGS="--json"
```

## Version Locations

| File | Field | Description |
|------|-------|-------------|
| `pubspec.yaml` | `liboqs.native_version` | Native library version |
| `pubspec.yaml` | `version` | Dart package version |
| `CHANGELOG.md` | Latest entry | What changed |

## After CI Builds

When CI completes after pushing:

1. Native libraries are built for all platforms
2. Artifacts are combined
3. FFI bindings are regenerated (if API changed)
4. Changes are committed back to repo

## Troubleshooting

### "No updates available"
- You're already on the latest version
- Check https://github.com/open-quantum-safe/liboqs/releases

### "Binding generation failed"
- New liboqs version may have breaking API changes
- Check liboqs release notes
- May need to update wrapper code in `lib/src/`

### Tests fail after update
- API may have changed
- Check if algorithm names changed
- Review liboqs changelog for breaking changes

## Upstream Resources

- [liboqs Releases](https://github.com/open-quantum-safe/liboqs/releases)
- [liboqs Changelog](https://github.com/open-quantum-safe/liboqs/blob/main/CHANGELOG.md)
- [liboqs Security](https://github.com/open-quantum-safe/liboqs/blob/main/SECURITY.md)
