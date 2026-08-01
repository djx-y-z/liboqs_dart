## [Unreleased]

### For Users

#### ✨ Highlights

- **Third-party notices now ship with the package** — `THIRD_PARTY_NOTICES.txt`
  carries the attribution for the third-party code compiled into the native
  library, both at the package root and inside every native release archive.
  Redistributors of an app embedding this package need it; see *Third-party
  notices* in the README for how to surface it in-app.
- **Consuming projects build faster** — the Build Hook stopped re-running on
  every single build and now reuses its cached result.
- **Dart API unchanged** — nothing to migrate. `KEM`, `Signature` and
  `OQSRandom` are exactly as in 2.0.0, and the bundled liboqs is still 0.16.0.

#### Added

- **`THIRD_PARTY_NOTICES.txt` — attribution for the code inside the native
  library.** liboqs is MIT "in general", and its own `LICENSE.txt` says the rest
  out loud: "liboqs includes some third party libraries or modules that are
  licensed differently; the corresponding subfolder contains the license that
  applies in that case." This package was shipping a compiled binary containing
  that code while carrying only the top-level MIT — so the notices Apache-2.0,
  BSD-3-Clause and the various public-domain dedications require were not
  travelling with it. Flutter's `LicenseRegistry` does not close this: it
  collects LICENSE files of pub packages, not of C code compiled into a native
  library. The file now ships at the root of the package and inside every native
  release archive, and the README explains how to surface it in an app.

  Two findings from building it are worth stating, because they are what the
  inventory is actually for. `src/common/common.c` is `Apache-2.0 AND MIT` — a
  conjunction, not a choice — and it is linked into all eleven artifacts, so
  Apache-2.0's terms bind every binary this package ships. And one file in the
  Keccak tree, `KeccakP-1600-AVX2.S`, is under the CRYPTOGAMS licence rather
  than the CC0 waiver the directory around it carries; it has no SPDX identifier
  and no licence file, so nothing short of reading the header would have found
  it.

#### Fixed

- **The Build Hook no longer re-runs on every build.** `hook/build.dart` declared
  the `.skip_liboqs_hook` marker as a build dependency unconditionally, and
  `hooks_runner` reports a declared file that does not exist as modified during
  the build — so every build in a consuming project re-ran the hook instead of
  reusing its cached result. The marker is now declared only while it exists,
  which is the only direction that needs invalidation: when `make build` removes
  it, the skipped result is dropped. A marker created after a full run leaves that
  run cached, and downloading nothing is exactly what the marker asks for.

### For Contributors

#### Added

- **`make third-party-notices` / `make verify-third-party-notices`** generate and
  check the notice inventory. The generator resolves each liboqs source through
  its own SPDX tag, then the nearest licence file, then
  `docs/algorithms/<class>/<family>.yml`, then an explicit override — and fails
  on a source matched by none of them, so a liboqs release that vendors an
  unfamiliar licence stops for a person instead of being filed under MIT.
  A single walk up to the nearest LICENSE, which is the obvious implementation,
  would have been wrong about 43% of the sources: 2532 of the 5957 files under
  `src/` have no licence file anywhere between them and the repository root.
  Verification is byte-exact and runs in the test workflow, before the native
  build, and in both release preflights; `.gitattributes` marks the file `-text`
  so a clean checkout materialises the same bytes the generator wrote.

  The inventory covers the whole liboqs tree minus `src/sig_stfl/`, which is not
  a shortcut: the union of the real link lines across all eleven shipped
  artifacts implicates 151 of the tree's 153 licence files, and the two it omits
  are exactly the stateful-signature ones. Deriving it from the sources rather
  than from a configured build is what lets the check be byte-exact at all — an
  inventory built from CMake would depend on whether the host had Xcode and an
  NDK.
- **`make lint-workflows` and `make check-action-pins`** run in CI as one fast
  job, covering the two workflows nothing else touches before a release.
  actionlint reads the workflows statically — expressions, `needs`/`steps`
  references, runner labels, the reusable-workflow contract, and shellcheck over
  every `run:` block — and is pinned by version *and* SHA256, because release
  assets are mutable. `check-action-pins` resolves every third-party `uses:`
  against the GitHub API, which actionlint cannot do: it is entirely offline, and
  on an action ref its bundled snapshot does not recognise it silently switches
  its checks off rather than reporting one, so a fabricated `@v999` or a made-up
  40-character SHA passes it without a word. Adopting actionlint also required
  suppressing two of its findings in `.github/actionlint.yaml` — its snapshot
  predates `create-github-app-token`'s `client-id`, so it is wrong about the very
  change made above.

#### Changed

- **Quoted every `>> "$GITHUB_OUTPUT"`-style redirect** across the workflows and
  the `setup-fvm` composite action, and grouped the three step-summary blocks
  into a single redirect. All 25 were shellcheck `SC2086` findings surfaced by
  the new lint job. None could actually misbehave — GitHub sets those paths to
  space-free values — but they are fixed rather than suppressed, so the rule stays
  live to catch a word-splitting bug that would matter.
- **GitHub Actions moved to their current majors** — `actions/checkout` v4→v7,
  `actions/upload-artifact` v4→v7, `actions/download-artifact` v4→v8,
  `actions/cache` v4→v6, `actions/create-github-app-token` v2→v3,
  `android-actions/setup-android` v3.2.2→v4.0.1 and
  `schneegans/dynamic-badges-action` v1.7.0→v1.9.0. Mostly the Node 20→24
  runtime migration, which needs no change on GitHub-hosted runners. Two are
  worth knowing about: `download-artifact` v8 now *fails* a run on an artifact
  digest mismatch instead of logging a warning, which is a welcome hardening of
  the `create-release` job that packages the native archives consumers download;
  and `checkout` v7 refuses to check out a fork PR under `pull_request_target` /
  `workflow_run`, which does not affect this repo — `pull_request_target` is
  never used, and the one `workflow_run` trigger (`test.yml`, after
  `build-liboqs.yml`) fires off a tag push or a dispatch, so the guard short-
  circuits before it can apply. Artifact layout is unchanged: v5's breaking path
  fix only covers single downloads by `artifact-ids`, while `create-release`
  downloads every artifact by name into `artifacts/<name>/`.
- **`create-github-app-token` is called with `client-id`** — the v2→v3 bump above
  made every run that mints an App token annotate `Input 'app-id' has been
  deprecated with message: Use 'client-id' instead.` The rename is the entire
  change: the action collapses `client-id || app-id` into a single value and
  passes it as the JWT `iss` claim, and GitHub has accepted either the numeric
  App ID or the `Iv23…` client ID there since May 2024 — so `vars.APP_ID` keeps
  both its name and its value, and no repository variable had to be created.
  `app-id` is deprecated by annotation only, with no removal scheduled, so this
  is cosmetic; it is worth doing because the warning was otherwise printed by
  `check-liboqs-updates.yml` on every daily run and by `build-liboqs.yml` on
  every native release.
- **Dependabot branches are exempt from the branch rulesets** — `Signing commit`
  applies `non_fast_forward` to `~ALL` branches with no bypass actors, so
  Dependabot, which refreshes an open PR by force-pushing a rewritten commit,
  could never rebase one onto a moved `main`; its first scheduled run gave up
  with "because the branch … is protected it was unable to do so", leaving the
  PR frozen at the day it was opened. `refs/heads/dependabot/**/*` is now
  excluded from that ruleset and from `Delete branches` (which blocked
  `@dependabot recreate` and branch cleanup for the same reason). Nothing is
  weakened: Dependabot signs its commits regardless of the rule, and `main`
  keeps both its pull-request gate and `required_signatures`. The trailing `/*`
  is load-bearing — these are `fnmatch` patterns in pathname mode, so a bare
  `**` stops at the first `/` and would miss the multi-segment names Dependabot
  actually generates.

#### Fixed

- **`make release` failed its own validation step, so no release could be cut.**
  It bumped `pubspec.yaml` and finalized the CHANGELOG, then ran
  `make publish-dry-run` on that bumped-but-uncommitted tree — and pub answers a
  modified tracked file with "checked-in files are modified in git", which is a
  *warning*, and `dart pub publish --dry-run` exits 65 on any warning at all.
  The step's own comment asserted the opposite ("pub exits 0 on warnings"), so
  the release aborted and reverted every time, on a state it had created itself.
  The dry-run now runs before the bump, on the clean tree, which is where the
  sibling template has had it since it introduced the two-stage flow. Catching
  power is unchanged: the dry-run validates package structure — files present,
  archive size, pubspec validity — and neither a version bump nor a CHANGELOG
  edit can affect that. Nothing is modified at that point either, so the revert
  path it needed is gone with it.
  `insertChangelogEntry` matched the target subsection with
  `line.startsWith('#### Changed')`, which also matches
  `#### Changed (Breaking)`. Because the branch fires once per matching heading,
  an `[Unreleased]` section carrying both subsections — the shape this
  CHANGELOG's 2.0.0 section already has — got the routine dependency bump
  announced as a breaking change *and* repeated under the real `#### Changed`.
  When only the breaking variant was present, `#### Changed` was never created
  at all. The heading is now matched exactly, and a `#### Changed` that has to
  be created is anchored just before the first subsection that follows it in the
  documented order (`#### Security`, `#### Fixed`, …) instead of being appended
  below them. Missing `#### ✨ Highlights` likewise moves to the top of the
  `### For Users` block rather than wherever the scan happened to be. Backported
  from the copier template, whose generated projects share this script; the two
  failure shapes are now covered in `test/scripts/release_test.dart`, which had
  no case with a breaking subsection present.
- **The FVM cache in CI never saved anything.** `setup-fvm` cached `~/.fvm`, but
  `.fvm` is FVM's *project-local* directory name — installed SDKs live in
  `$HOME/fvm/versions` (`fvmDir = cachePath ?? $HOME/fvm` in FVM 4.x). That path
  never existed, so `actions/cache` ended every job with `Path Validation Error:
  … hence no cache is being saved` in a green post-step, the repository held no
  cache entries at all, and each job on all four platforms reinstalled Flutter
  from scratch (~80 s apiece). The action now caches `~/fvm/versions` and makes
  that location a contract rather than a guess: `FVM_CACHE_PATH` is set
  explicitly, and FVM itself is pinned to 4.1.2 (exposed as the action's
  `fvm-version` input, since Dependabot cannot see a `dart pub global activate`
  line) so no unannounced major can relocate the SDKs. A step after
  `fvm install` then *fails* the job if they land anywhere else —
  annotate-and-continue is precisely the mode that hid this bug for months, so it
  is not the safe option but the broken one with a louder log line, and nothing
  irreversible sits behind the check: setup-fvm runs before the release archives,
  the tag and the pub.dev publish, so a release is re-run rather than broken.
  Two latent problems came out with it: the key gained `runner.arch`, because
  `ubuntu-latest` and `ubuntu-24.04-arm` both report `runner.os == 'Linux'` and
  shared one key — the first working save would have handed an x86-64 SDK to the
  ARM64 runner — and `restore-keys` is gone, since a partial hit restores the
  previous SDK, `fvm install` adds the new one beside it, and the cache would grow
  by ~2.5 GB with every Flutter bump. Verified on `main`: four entries saved, one
  per (OS, arch), 700–710 MiB each (1.2–1.3 GB unpacked), and no more
  `Path Validation Error`.
- **Pull requests that only touch CI ran no checks at all.** `test.yml` filtered
  on `lib/**`, `test/**` and `pubspec.yaml` (plus its own two workflow files on
  push), so a Dependabot action bump could merge unverified — #5 had to be
  validated by hand with `workflow_dispatch` on the PR branch — and even a
  matching path would then have been skipped by `user.type != 'Bot'`, a guard
  meant only for the liboqs update PRs. `.github/**` is now covered on both
  `pull_request` and `push`, and update PRs are matched by branch name
  (`update-liboqs-*`, created by `check-liboqs-updates.yml`) instead of author
  type, so Dependabot PRs run the full matrix while `native_version` bumps keep
  skipping until their native libraries exist. A `pull_request` run resolves
  `test-reusable.yml` and `.github/actions/*` from the PR's merge ref, so a
  bumped action really does execute; the `push` filter earns its place too,
  because PR runs may read the base branch's cache scope but never the reverse —
  without a run on `main` after each CI change, every PR's first run would start
  from a cold FVM cache. `hook/**`, `scripts/**` and `Makefile` joined the same
  filters for the same reason one level down: `test/hook/build_hook_test.dart` and
  `test/scripts/release_test.dart` cover exactly those, so a change to the Build
  Hook or to the release scripts was the one commit its own tests never ran on.
- **A broken liboqs update checker looked exactly like "up to date".** The
  scheduled check ran `make check … || true`, which it has to: the checker exits 1
  to signal "update available", and GNU make collapses any non-zero recipe status
  into its own exit 2, so the exit code cannot tell that apart from a crash (rate
  limit, API change, network) — an available update and a rejected `--version`
  argument both come back as `make` exit 2. The step now gates on the artefact
  instead — the checker writes `needs_update=` to `GITHUB_OUTPUT` before
  signalling, and not at all when it throws — and fails the run when that line is
  missing rather than reporting the current version as the latest forever. Both
  paths were exercised locally through the real target. The manually dispatched
  `target_version` is shape-checked in the workflow as well, before it is
  interpolated into `make check ARGS=…` where a `;` would reach the recipe shell.
- **A release could be aborted by an unrelated diverged tag.** `make release` and
  `make release-native` fetched `origin --tags`, so a single diverged tag anywhere
  in the namespace failed the fetch and stopped the release. Both now fetch
  `origin main --no-tags`: the behind/ahead check needs only `origin/main`, and the
  "tag already on origin?" check asks `git ls-remote` directly.
- **Upstream version tags are validated on every path, not just the API
  response.** `validateUpstreamTag` (exported and covered by
  `test/scripts/check_updates_test.dart`) now also guards the `--version` argument
  passed by hand and the version recorded in `pubspec.yaml` — both reach
  `GITHUB_OUTPUT`, a branch name and a `make` recipe. Its pattern additionally
  rejects non-canonical segments such as `0.016.0`, which the previous `\d+` groups
  accepted.
- **Releasing no longer leaves an empty `## [Unreleased]` behind.**
  `finalizeChangelog` renames the heading in place, so an empty section stops
  shipping to pub.dev with every release; the scripts that record unreleased
  changes create the section when it is absent, and the footer `[Unreleased]:`
  compare link — load-bearing, it carries the repo URL and the previous version —
  is deliberately kept. Relatedly, when `## [Unreleased]` exists without a
  `### For Users` subsection, `insertChangelogEntry` now creates one at the top of
  the section instead of appending it below `### For Contributors`, and no longer
  duplicates the `### For Users` heading when the section ends with one.

## [2.0.0] - 2026-07-20

### For Users

#### ✨ Highlights

- **Bundled liboqs upgraded 0.15.0 → 0.16.0 (breaking)** — includes upstream
  security fixes (see Security) plus the algorithm removals and renames below.
- **Dart API unchanged** — `KEM`, `Signature`, and `OQSRandom` are
  source-compatible; every breaking change is in *algorithm availability* or the
  bundled native library, not the class API.
- **SPHINCS+ removed (breaking)** — `Signature.create('SPHINCS+-…')` now throws
  `LibOQSException`; migrate to **SLH-DSA** (FIPS 205) or **ML-DSA** (FIPS 204).
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
  2025-08-22 specification. `KEM.create('HQC-128')` now throws `LibOQSException`.

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
- MQOM signature scheme family (12 `mqom2_cat{1,3,5}_gf16_{fast,short}_r{3,5}`
  parameter sets) — a candidate in NIST's Additional Digital Signatures
  process, new upstream in liboqs 0.16.0 and enabled by default.
- Upstream runtime-detection API for stateful signature support (`OQS_SIG_STFL_*`).

#### Removed (Breaking)

- SPHINCS+ signature algorithms — all 12 `*-simple` variants of both the
  `SPHINCS+-SHA2-*` and `SPHINCS+-SHAKE-*` families — were removed upstream in
  liboqs 0.16.0. `Signature.create('SPHINCS+-…')` now throws `LibOQSException`.
  Migrate to **SLH-DSA** (FIPS 205, `SLH_DSA_PURE_*`) or **ML-DSA** (FIPS 204).
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
- Build hook: download/cache resilience against partial and transient failures.
  A cache entry is now reused only after a `.download-complete` marker proves
  the extraction finished, so an interrupted `tar` no longer leaves a truncated
  library that is registered and reused forever; and both the checksums fetch
  and the binary download now retry on transient HTTP 5xx/429 instead of failing
  the build on a single network blip.

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
- **Build provenance attestation** for the native release archives:
  `build-liboqs.yml` attests every archive with GitHub Artifact Attestations
  (Sigstore, SLSA Build L2) and attaches the Sigstore bundle
  (`liboqs-<fullVersion>.sigstore.jsonl`) to the release, so any downloaded
  binary can be verified — online or fully offline — with
  `gh attestation verify` (see SECURITY.md → Authenticity). This breaks the
  self-trust of the same-release SHA256 checksums file.
- Dependabot for GitHub Actions (`.github/dependabot.yml`): weekly grouped
  update PRs (Monday 06:00 UTC, `chore(deps)` prefix) bump the pinned actions —
  commit SHA and its version comment — across the workflows and the composite
  actions, so the SHA pins from the supply-chain audit don't go stale.

#### Changed

- Regenerated FFI bindings for liboqs 0.16.0.
- **CI hardening & reliability (Phase 4).** Workflows now run with a
  least-privilege `GITHUB_TOKEN` (workflow-level `contents: read`; only the
  release-publishing jobs opt up to the specific writes they need). The
  native-library build workflow serializes concurrent runs for the same ref
  via a `concurrency` group. Windows
  runners install GNU Make from a pinned GitHub release (with retry + size check)
  via a `setup-make` composite action instead of Chocolatey. The
  deployment-target guard (`make check-targets`) runs in the CI quality checks
  alongside `analyze`/`format-check`. The publish workflow gained a dedicated
  package-validation (`publish-dry-run`) job that gates publishing. The liboqs
  update checker skips when an open update PR for the same version already
  exists, so scheduled runs no longer force-push over manual commits on that PR.
- **CI supply-chain hardening (pre-release audit).** The upstream version tag
  from the liboqs update check is format-validated before it reaches
  `GITHUB_OUTPUT`, and workflow `run:` blocks read it (and the other step
  outputs) via `env:` instead of inline `${{ }}` interpolation — closing a
  shell-injection path from upstream release names. Third-party GitHub Actions
  are pinned to commit SHAs, and the Windows GNU Make helper binary is verified
  against a hardcoded SHA256 before use.
- **Tag-triggered native builds.** `build-liboqs.yml` now triggers on a
  `liboqs-<fullVersion>` tag push (created by `make release-native`) instead of
  every `pubspec.yaml` push to `main`: merging a version bump no longer builds
  or publishes anything by itself, the tag is validated against `pubspec.yaml`
  at the tagged commit, the GitHub Release is created on that same tag (the
  delete-then-recreate step is gone), and the release-publishing job is gated
  by the `native-build` environment (mirrors the pub.dev publish gate; inert
  until reviewers are configured).
- **Release notes hardened against changelog injection.** `publish.yml` now
  passes the version and changelog through `env:` and writes the release notes
  with `printf` to a `--notes-file`, so a literal `EOF` line in the changelog
  can no longer terminate the inline heredoc early and execute the remaining
  text as shell under the `contents: write` token.
- **Release-exists CI probe fails closed.** `check_release.dart` now
  distinguishes exists / missing / inconclusive and aborts (exit 1) on an API
  error or network failure instead of reporting the release as absent and
  letting a build proceed on a wrong assumption.
- **Release-script robustness.** `runInherit` fails loud on any non-zero exit
  (previously swallowed when no failure message was passed), `finalizeChangelog`
  validates the `--date` (`YYYY-MM-DD`) before stamping the immutable released
  heading, and the commit-failure message now states the version bump is left
  staged and how to recover.

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
