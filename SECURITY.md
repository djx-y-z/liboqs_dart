# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

Only the latest minor version receives security updates. We recommend always using the latest version.

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
- **Build pipeline integrity** (CI/CD security)

### Out of Scope

The following are handled by the upstream liboqs project:

- Cryptographic algorithm implementations
- Side-channel attack resistance
- Algorithm security proofs

For vulnerabilities in the underlying algorithms, please report to the [Open Quantum Safe project](https://openquantumsafe.org/).

### Threat Model Limitations

This library inherits the [liboqs threat model](https://github.com/open-quantum-safe/liboqs/blob/main/SECURITY.md):

- **Not in scope**: Physical side-channels (power analysis, electromagnetic emissions)
- **Not in scope**: Fault injection attacks (Rowhammer, voltage glitching)
- **Not in scope**: Hardware vulnerabilities

## Security Updates

### Automatic Updates

Native libraries are automatically rebuilt when new liboqs versions are released via GitHub Actions. Subscribe to releases to stay informed.

### Checking for Updates

```bash
# Check if a newer liboqs version is available
make check

# Apply updates
make check ARGS="--update"
```

## Best Practices

When using this library:

1. **Always call `dispose()`** on KEM and Signature instances to securely clear native resources
2. **Call `clearSecrets()`** on key pairs and encapsulation results when done to zero sensitive data in Dart memory
3. **Use `LibOQSUtils.constantTimeEquals()`** for comparing secrets (prevents timing attacks)
4. **Keep the library updated** to the latest version
5. **Use NIST-standardized algorithms** (ML-KEM, ML-DSA, SLH-DSA) for production
6. **Follow secure key storage practices** for your platform
7. **Never log or print** the output of `toStrings()` or `toHexStrings()` - they contain secret keys

### Memory Security

- Native memory is securely zeroed using `OQS_MEM_secure_free` before deallocation
- **Automatic cleanup**: Finalizers automatically zero secrets when objects are garbage collected (defense-in-depth)
- **Explicit cleanup** (recommended): Call `clearSecrets()` for immediate zeroing - don't rely solely on GC timing
- Use `publicKeyBase64` / `publicKeyHex` getters for safe serialization of public keys only
- `constantTimeEquals()` uses secure memory handling internally (no timing leaks, secure buffer cleanup)

## Related Security Resources

- [liboqs Security Policy](https://github.com/open-quantum-safe/liboqs/blob/main/SECURITY.md)
- [NIST Post-Quantum Cryptography](https://csrc.nist.gov/projects/post-quantum-cryptography)
- [Open Quantum Safe Project](https://openquantumsafe.org/)
