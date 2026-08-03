---
name: release-package
description: Prepare a new version of the liboqs package for publication to pub.dev. Use when user wants to release, publish, or tag a new version of the package.
---

# Release the Dart Package

Guide for publishing a new version of the `liboqs` Dart package to pub.dev.

> **Prerequisite: the native release must already exist.** The published
> package's build hook downloads the precompiled native libraries from the
> GitHub Release `liboqs-<native_version>-<native_build>` (e.g.
> `liboqs-0.16.0-1`). That release is created by `build-liboqs.yml`, which
> triggers on a push of the `liboqs-<fullVersion>` tag — merging a version
> bump into `main` does NOT start a build by itself. So: merge your changes
> into `main`, run `make release-native` (creates and pushes the signed tag),
> let the native build finish, then release. `make release` verifies the
> release exists automatically (see below).

> **One-time note for 2.0.0:** the `## [2.0.0]` CHANGELOG section was
> finalized (with a date) ahead of the actual release, and `pubspec.yaml`
> already says `2.0.0` — so `make release` cannot be used for it. Release
> 2.0.0 via the Manual fallback below (update the `## [2.0.0]` date to the
> actual release day first). The scripted flow applies from **2.0.1** onward.

## How to run

```bash
# 0. Your SSH signing key must be in ssh-agent (commits/tags are signed):
ssh-add -l   # if empty: ssh-add ~/.ssh/<your-signing-key>

# If the native release liboqs-<fullVersion> doesn't exist yet
# (first release after a liboqs bump), tag-trigger the native build and
# wait for it to finish:
make release-native

# From a clean, up-to-date main, after the native build has finished:
make release ARGS="--version 2.1.0"
```

`make release` (`scripts/release.dart`) does the whole release in one command:

1. **Preconditions** — refuses unless you are on a clean `main`, up to date
   with `origin/main`, the version is greater than the current `pubspec.yaml`
   version, and the `vX.Y.Z` tag does not already exist (local or remote).
2. **Verifies the native release exists** — checks that the GitHub Release
   `liboqs-<native_version>-<native_build>` is published (via `gh`). Fails
   closed if it is missing or can't be verified — the published build hook
   downloads it, so releasing without it would break consumers.
3. **Bumps** the `version:` in `pubspec.yaml`.
4. **Finalizes the CHANGELOG** — renames `## [Unreleased]` to `## [X.Y.Z] -
   <today>` in place (no empty `## [Unreleased]` is left behind) and updates the
   bottom compare links (`[Unreleased]` → `vX.Y.Z...HEAD` and a new `[X.Y.Z]` →
   `vPREV...vX.Y.Z`).
5. **Validates** the package with `make publish-dry-run` (reverts the file
   changes and aborts if it reports errors).
6. Shows the diff and asks for confirmation (skip with `--yes`).
7. Creates a **signed commit** and a **signed tag** `vX.Y.Z`.
8. **Pushes** `main` and the tag (skip with `--no-push`), which triggers
   `publish.yml` → pub.dev.

### Signing

Commits and tags are signed with the SSH signing key from your git config.
Loading the key into `ssh-agent` before running `make release` (`ssh-add -l` to
check) avoids the passphrase prompt entirely. Run from a terminal (not an IDE
task runner) so the pre-commit hook (`format-check` + `analyze`) and any
interactive prompt work.

**Get the passphrase wrong and it just asks again.** `ssh-keygen` does not
re-prompt on its own, so a mistyped passphrase used to abort the release
outright. Every signing and push step now prints the error and runs itself
again, so the passphrase prompt comes straight back — no question to answer, no
attempt limit. **Ctrl-C is how you give up.** From the third failure in a row it
pauses 2s between attempts and says so, so a step failing for a reason no
passphrase will fix cannot scroll past you. With a non-interactive stdin (CI)
there is no retry at all: the step throws on its first failure, as before.

**A run that died anyway is resumed by re-running the exact same command.** If
you Ctrl-C out or lose the terminal after the release commit was created,
`make release` detects that commit and continues from the tag/push step — it
does not bump the version or edit the CHANGELOG a second time, and interrupting
it *before* the commit gets you the one command that discards the half-applied
edits. `make release-native` does the same for its own stranded state (tag
created, push failed): re-running pushes the existing tag. Nothing has to be
reverted or tagged by hand.

### Options

- `--version <X.Y.Z>` — new package version (required)
- `--no-push` — commit and tag locally only (push later yourself)
- `--yes`, `-y` — skip the confirmation prompt
- `--skip-release-check` — skip the native-release existence check (only if
  you have verified the `liboqs-<fullVersion>` release exists manually)
- `--date <Y-M-D>` — CHANGELOG date to stamp (default: today)

## CHANGELOG convention

Between releases, changes accumulate under a `## [Unreleased]` section.
Releasing consumes that section — the heading is renamed in place — so right
after a release there is **no** `## [Unreleased]` heading: whoever records the
next change recreates it (`make update-changelog` does it automatically for
liboqs bumps; add it by hand for anything else). `make release` requires the
section and fails without it, which is the intended guard: a release with
nothing recorded is a mistake.

The `[Unreleased]` compare link at the bottom of the CHANGELOG must always
exist — it is the single source of truth for the repo URL and the previous
version, read by `make release` and by the section-creating scripts. It stays
even while no heading references it; do not delete it as stale.

## Choosing the version (SemVer for the Dart package)

The pub.dev package version follows [Semantic Versioning](https://semver.org/)
for the **public Dart API and the exposed algorithm set**, independent of the
bundled liboqs version.

| Change Type | Version Bump | Examples |
|-------------|--------------|----------|
| Breaking changes | MAJOR | Removed/renamed public APIs; algorithms removed/renamed upstream; wire-format changes |
| New features | MINOR | New public APIs, new algorithms enabled, new platform support |
| Bug fixes | PATCH | Bug fixes, non-breaking native-library rebuilds, documentation |

Note that a liboqs bump alone can force a MAJOR: removing or renaming an
algorithm changes what `KEM.create()` / `Signature.create()` accepts. The
CHANGELOG (`[Unreleased]` section) is the source of truth for what changed —
review it and pick the bump that matches. See the changelog format in
`CLAUDE.md` → Changelog Format.

## Publishing flow

This project uses **tag-triggered CI** for publishing — you do NOT run `dart
pub publish` manually:

1. `make release` pushes a git tag matching `vX.Y.Z`.
2. The `publish.yml` workflow triggers automatically on the tag.
3. It validates the tag matches `pubspec.yaml`, runs tests and a
   `publish-dry-run` validation job, and publishes to pub.dev via OIDC (gated
   by the `pub.dev` environment).
4. It creates a GitHub Release with the extracted changelog section.

## Manual fallback

If you cannot use `make release` (e.g. `make`/`gh` unavailable, or the
one-time 2.0.0 case above):

```bash
# 1. Quality checks
make analyze && make test && make format-check

# 2. Bump pubspec.yaml `version:` and finalize CHANGELOG.md:
#    - rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`
#      (for 2.0.0: the section already exists — just correct its date)
#    - do NOT add a fresh empty `## [Unreleased]`; the next change recreates it
#    - rewrite `[Unreleased]: .../compare/vX.Y.Z...HEAD` and add
#      `[X.Y.Z]: .../compare/vPREV...vX.Y.Z` at the bottom
#      (for 2.0.0: both links already exist)

# 3. Validate
make publish-dry-run

# 4. Commit (signed), tag (signed, annotated), push
git commit -am "chore: prepare release vX.Y.Z"
git tag -s vX.Y.Z -m "Release vX.Y.Z"
git push origin main && git push origin vX.Y.Z
```

### If CI fails

Fix the issue, then delete and re-create the tag:

```bash
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z
# fix + commit on main, then re-run:
make release ARGS="--version X.Y.Z"
```

## Resources

- Publish workflow: `.github/workflows/publish.yml`
- Release script: `scripts/release.dart` (logic in `scripts/src/release.dart`)
- Native release script: `make release-native` (`scripts/release_native.dart`)
- Native build workflow: `.github/workflows/build-liboqs.yml` (tag-triggered:
  `liboqs-<fullVersion>`)
- Repo protections (release tags, native-build environment):
  `.github/rulesets/README.md`
- AI changelog for liboqs bumps: `make update-changelog`
  (`scripts/update_changelog.dart`, used by `check-liboqs-updates.yml`)
- [pub.dev Publishing Guide](https://dart.dev/tools/pub/publishing)
- [Semantic Versioning](https://semver.org/) · [Keep a Changelog](https://keepachangelog.com/)
