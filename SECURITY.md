# Security Policy

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

### How to Report

Use [GitHub Security Advisories](https://github.com/djx-y-z/liboqs_dart/security/advisories/new) to report vulnerabilities privately. This allows us to assess the risk and prepare a fix before public disclosure.

When reporting, please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix timeline**: Depends on severity, typically 30-90 days

### Coordinated Disclosure

We follow coordinated disclosure practices. Once a fix is available, we will:

1. Release a patched version
2. Publish a security advisory
3. Credit the reporter (unless anonymity is requested)

## Security Scope

### In Scope

This package provides Dart FFI bindings to [liboqs](https://github.com/open-quantum-safe/liboqs). Our security scope includes:

- **Memory safety** in Dart FFI wrapper code
- **Correct API usage** of underlying liboqs functions
- **Secure memory handling** (zeroing sensitive data before freeing)
- **Supply chain integrity** of the prebuilt native libraries (build pipeline, download verification)

### Out of Scope

The following are handled by the upstream liboqs project:

- Cryptographic algorithm implementations
- Side-channel attack resistance of the algorithm code
- Algorithm security proofs

For vulnerabilities in the underlying algorithms, please report to the [Open Quantum Safe project](https://openquantumsafe.org/).

### Threat Model Limitations

This library inherits the [liboqs threat model](https://github.com/open-quantum-safe/liboqs/blob/main/SECURITY.md):

- **Not in scope**: Physical side-channels (power analysis, electromagnetic emissions)
- **Not in scope**: Fault injection attacks (Rowhammer, voltage glitching)
- **Not in scope**: Hardware vulnerabilities

## Architecture Overview

This library binds the **C** liboqs library directly via `dart:ffi`. Unlike
wrappers built on opaque handles (where secrets stay behind the FFI boundary),
this package **returns key material into Dart by design**: `KEMKeyPair.secretKey`,
`KEMEncapsulationResult.sharedSecret`, and `SignatureKeyPair.secretKey` are plain
`Uint8List`s on the Dart heap. That makes the API simple and storage-agnostic,
but it also means secret hygiene is a shared responsibility between the library
and your application — the sections below spell out exactly what the library
guarantees and what it cannot.

**Key security properties:**

- Native buffers that held secrets are zeroed with liboqs' `OQS_MEM_secure_free`
  (designed to resist compiler dead-store elimination) before being freed, in
  `finally` blocks, on every code path.
- Dart-side secrets can be zeroed explicitly (`clearSecrets()`), and a
  `Finalizer` zeroes them automatically when the owning object is garbage
  collected (defense-in-depth).
- Secret comparisons go through a constant-time native primitive
  (`OQS_MEM_secure_bcmp`).
- The prebuilt native library is verified against a SHA256 checksum
  **fail-closed** at download time (see Supply Chain Security).

## Secret Lifetime and Memory Model

Secrets exist in two places, with different guarantees:

### Native memory (transient, library-managed)

Every FFI call copies inputs into freshly allocated native buffers and copies
outputs back into Dart. The library frees these buffers in `finally` blocks:

- Buffers that held **secret keys, shared secrets, or seeds** are released with
  `OQS_MEM_secure_free`, which zeroes the memory before freeing it.
- Buffers that held only **public data** (public keys, ciphertexts, signatures,
  messages) are released with a plain free.

This bounds the native residency of a secret to the duration of the call.

### Dart memory (long-lived, shared responsibility)

The `Uint8List` secrets returned to you live on the Dart garbage-collected
heap. The library gives you two tools:

- **`clearSecrets()`** (on `KEMKeyPair`, `KEMEncapsulationResult`, and
  `SignatureKeyPair`) zeroes the secret bytes immediately, using liboqs'
  `OQS_MEM_cleanse` internally. Call it in a `finally` block as soon as the
  secret is no longer needed.
- **Automatic finalizers**: each secret-bearing object registers a `Finalizer`
  that zeroes the secret when the object is garbage collected. This is
  defense-in-depth for the case where `clearSecrets()` was forgotten — GC
  timing is non-deterministic, so do not rely on it as the primary mechanism.

**The honest caveat:** zeroing memory on a garbage-collected heap is
**best-effort defense-in-depth, not erasure**. The Dart VM's collectors may
move or copy live objects during collection, and neither the vacated space nor
freed blocks are sanitized by the VM. A secret that has lived through a GC
cycle may have left an unwiped copy behind that `clearSecrets()` cannot reach.
Practical consequences:

- Minimize the window: create the secret, use it, `clearSecrets()` in
  `finally`.
- Avoid making copies. `sublist()`, `toList()`, spread operators,
  `base64Encode`, and string conversions all create additional unwiped copies
  of the secret that you would have to track and zero yourself.
- For long-term storage, move secrets into platform secure storage (Keychain,
  Keystore, TPM-backed stores) promptly and clear the in-memory copy.

### Instance lifecycle: `dispose()`

`KEM` and `Signature` instances wrap a native `OQS_KEM`/`OQS_SIG` structure
(algorithm metadata and function pointers — no key material). Call `dispose()`
when done to free the native structure deterministically; a `Finalizer` frees
it on GC otherwise. Using an instance after `dispose()` throws a `StateError`.
The internal cleanup order (free native memory → detach finalizer → set the
disposed flag) prevents leaks if an exception occurs mid-cleanup.

`LibOQS.cleanup()` releases library-global resources (e.g. prefetched OpenSSL
objects) when your application is completely done with liboqs.

## Timing Attack Prevention

- **Never compare secrets with `==`, `listEquals`, or hand-written loops** —
  early-exit comparisons leak how many leading bytes matched.
- Use `LibOQSUtils.constantTimeEquals(a, b)`: it compares via liboqs'
  `OQS_MEM_secure_bcmp` and folds the length check in without an early exit,
  then securely frees its temporary native buffers.
- Cryptographic operations themselves (keygen, encaps/decaps, sign/verify) run
  inside upstream liboqs, whose implementations are designed to avoid
  secret-dependent timing; see the upstream threat model for the exact claims
  per algorithm.

```dart
// WRONG - not constant time
if (sharedSecretA.toString() == sharedSecretB.toString()) { ... }

// CORRECT
if (LibOQSUtils.constantTimeEquals(sharedSecretA, sharedSecretB)) { ... }
```

## Key Material Handling

Never let secrets reach logs, error messages, analytics, or crash reports:

```dart
// WRONG - toStrings() exports the SECRET KEY
print('Generated: ${keyPair.toStrings()}');

// CORRECT - safe getters expose only public data
print('Public key: ${keyPair.publicKeyBase64}');
```

- `toStrings()` / `toHexStrings()` on key pairs and encapsulation results
  **export the secret key / shared secret in plaintext**. They exist solely for
  moving secrets into secure storage. Never log or transmit their output over
  an insecure channel, and remember each call creates new unwiped copies (see
  the memory model above).
- Safe alternatives: `publicKeyBase64` / `publicKeyHex` (key pairs) and
  `ciphertextBase64` / `ciphertextHex` (encapsulation results) expose only
  shareable data.
- Library exceptions report lengths and status codes, never key bytes — keep
  your own error handling to the same standard.

## Randomness

`OQSRandom` wraps liboqs' `OQS_randombytes`:

- The default generator is the **system RNG** (`/dev/urandom`,
  `SecRandomCopyBytes`, `BCryptGenRandom`, …) — cryptographically secure on all
  supported platforms.
- `generateInt()` uses rejection sampling, so it is free of modulo bias.
- `switchAlgorithm()` can select a different upstream RNG (e.g. `"OpenSSL"`).
  Only do this if you understand the implications; `resetToDefault()` restores
  the system RNG. Never substitute a non-cryptographic RNG for key generation.

## Supply Chain Security

The native liboqs libraries are **built from source** by this repository's
GitHub Actions workflows — from a **pinned upstream release tag** (never a
moving branch) — published as GitHub Releases, and downloaded by the build hook
(`hook/build.dart`) at consumer build time.

- **Integrity (implemented):** every downloaded archive is verified against a
  SHA256 checksum published alongside it. Verification is **fail-closed** — if
  the checksums file cannot be fetched or has no entry for the archive, the
  build **aborts** instead of installing an unverified binary. The escape hatch
  `LIBOQS_ALLOW_UNVERIFIED_DOWNLOAD=1` exists only for building against old
  releases that predate checksum publication and should never be set in
  production.
- **Cache correctness (implemented):** downloads are cached keyed by the full
  native version **and** the platform variant (including the iOS
  device/simulator distinction), so a version bump can never silently reuse a
  stale binary and different targets cannot poison each other's cache.
- **Authenticity (not yet implemented):** the checksums file lives in the same
  GitHub Release as the archives, so SHA256 alone does not defend against a
  release or maintainer-token compromise — an attacker who can replace the
  archive can replace its checksum too. Cryptographic build provenance
  (attestation generated in CI and verified by the build hook) is the planned
  next step and is tracked as future work.

Reviewing upstream: each liboqs version bump lands via a pull request that
links the upstream release notes; upstream changes are reviewed before the
native libraries are rebuilt.

## Static Analysis and CI

Every push and pull request runs, on all supported desktop platforms:

- `make analyze` (with `--fatal-infos` locally) — Dart static analysis
- `make format-check` — formatting drift check
- `make test` — the full test suite, including the build-hook unit tests
- `make check-targets` — guards iOS/macOS deployment-target consistency across
  the native build scripts

CI workflows run with a least-privilege `GITHUB_TOKEN` (`contents: read` by
default; only the release-publishing job gets `contents: write`), and pub.dev
publishing uses OIDC — no long-lived publishing tokens exist.

## Best Practices

When using this library:

1. **Always call `dispose()`** on `KEM` and `Signature` instances to free
   native resources deterministically
2. **Call `clearSecrets()`** on key pairs and encapsulation results in a
   `finally` block as soon as the secret is no longer needed
3. **Use `LibOQSUtils.constantTimeEquals()`** for comparing secrets (prevents
   timing attacks)
4. **Keep the library updated** to the latest version
5. **Use NIST-standardized algorithms** (ML-KEM, ML-DSA, SLH-DSA) for
   production
6. **Follow secure key storage practices** for your platform (Keychain,
   Keystore, TPM-backed storage)
7. **Never log or print** the output of `toStrings()` or `toHexStrings()` —
   they contain secret keys
8. **Avoid copying secrets** (`sublist()`, string/base64 conversion) unless you
   also zero the copies

## Security Updates

### Updates

New liboqs versions are detected automatically (a bot PR bumps
`liboqs.native_version`); after the bump merges, a maintainer deliberately
triggers the native rebuild by pushing a signed `liboqs-<fullVersion>` tag
(`make release-native`) — builds are never started implicitly. Subscribe to
releases to stay informed.

### Checking for Updates

```bash
# Check if a newer liboqs version is available
make check

# Apply updates
make check ARGS="--update"
```

## Code Review Security Checklist

For contributors — when reviewing changes to the FFI wrapper, verify:

- [ ] Every native allocation is freed in a `finally` block
- [ ] Buffers that held secrets are freed with
      `LibOQSUtils.secureFreePointer(ptr, length)`, not `freePointer`
- [ ] New classes holding secrets provide `clearSecrets()` and attach the
      secret-zeroing `Finalizer`
- [ ] Native function pointers are null-checked before `asFunction()`
- [ ] Secret comparisons use `constantTimeEquals`, never `==` or loops
- [ ] No key material in exception messages, logs, or doc examples
- [ ] Methods that export secrets carry a `/// **Security Warning:**` doc
      comment and have a safe public-data alternative
- [ ] `dispose()` follows the order: free → detach finalizer → set flag

## Known Limitations

1. **Dart VM memory:** the garbage collector may move or copy secret bytes
   before they are zeroed, and does not sanitize vacated memory. Dart-side
   zeroing is defense-in-depth, not guaranteed erasure (see Secret Lifetime and
   Memory Model).
2. **Secrets cross the FFI boundary by design:** this package hands secret keys
   and shared secrets to Dart as `Uint8List`. If your threat model requires
   secrets to never exist in garbage-collected memory, you need a
   hardware-backed or opaque-handle design instead of this library.
3. **Timing side channels:** the wrapper's own secret handling is
   constant-time where it compares secrets; the algorithm implementations'
   side-channel properties are inherited from upstream liboqs.

## Related Security Resources

- [liboqs Security Policy](https://github.com/open-quantum-safe/liboqs/blob/main/SECURITY.md)
- [NIST Post-Quantum Cryptography](https://csrc.nist.gov/projects/post-quantum-cryptography)
- [Open Quantum Safe Project](https://openquantumsafe.org/)
