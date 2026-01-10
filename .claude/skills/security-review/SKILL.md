---
name: security-review
description: Review Dart FFI code for security issues in cryptographic contexts. Use when reviewing code changes, checking for memory leaks, verifying secure memory handling, or auditing cryptographic code.
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Security Review for liboqs_dart

Review code for security issues specific to this post-quantum cryptography FFI library.

## Security Checklist

### 1. Memory Management

**Secret Data (keys, shared secrets):**
- [ ] Use `LibOQSUtils.secureFreePointer(ptr, length)` - calls `OQS_MEM_secure_free`
- [ ] Never use `LibOQSUtils.freePointer()` for secrets

**Non-sensitive Data (public keys, ciphertext):**
- [ ] Use `LibOQSUtils.freePointer(ptr)` - standard free is OK

**Always:**
- [ ] Free memory in `finally` blocks to prevent leaks on exceptions

### 2. Classes Holding Secrets

Every class with secret data MUST have:

```dart
// 1. Finalizer for automatic cleanup (defense-in-depth)
final Finalizer<Uint8List> _secretDataFinalizer = Finalizer((data) {
  LibOQSUtils.zeroMemory(data);
});

// 2. In constructor - attach finalizer
_secretDataFinalizer.attach(this, secretKey, detach: this);

// 3. clearSecrets() method for explicit cleanup
void clearSecrets() {
  LibOQSUtils.zeroMemory(secretKey);
}
```

### 3. Comparisons

- [ ] Use `LibOQSUtils.constantTimeEquals()` for comparing secrets
- [ ] NEVER use `==` or loop-based comparison for secret data (timing attacks!)

### 4. Function Pointers

Before calling `.asFunction()` on native function pointers:

```dart
// CORRECT: Validate first
if (_ptr.ref.keypair == nullptr) {
  throw LibOQSException('keypair function pointer is null - corrupted');
}
final fn = _ptr.ref.keypair.asFunction<...>();

// WRONG: Direct call without validation
final fn = _ptr.ref.keypair.asFunction<...>(); // May crash!
```

### 5. dispose() Pattern

Order matters - prevents memory leaks if exception occurs:

```dart
void dispose() {
  if (!_disposed) {
    oqs.OQS_KEM_free(_kemPtr);      // 1. Free native memory
    _kemFinalizer.detach(this);      // 2. Detach finalizer
    _disposed = true;                 // 3. Set flag
  }
}
```

### 6. Documentation

Methods exposing secrets MUST have:

```dart
/// **Security Warning:** This method exports the SECRET KEY in plaintext.
/// Only use for secure storage. Never log the output.
```

### 7. What to Look For

**Red Flags:**
- `freePointer` used on secret keys or shared secrets
- Missing `clearSecrets()` method on classes with secrets
- Missing Finalizer attachment for secret data
- `==` used to compare keys or secrets
- Function pointer used without null check
- Missing `finally` block for memory cleanup
- Logging or printing of secret data

**Good Patterns:**
- `secureFreePointer` for all secrets
- `constantTimeEquals` for secret comparison
- Finalizers attached in constructors
- `clearSecrets()` available and documented
- Security warnings in docstrings

## Example Review Output

```
## Security Review: lib/src/new_feature.dart

### Issues Found

1. **Line 45**: Using `freePointer` for secret key
   - Severity: HIGH
   - Fix: Use `secureFreePointer(secretKeyPtr, secretKey.length)`

2. **Line 78**: Missing Finalizer for shared secret
   - Severity: MEDIUM
   - Fix: Add `_secretDataFinalizer.attach(this, sharedSecret, detach: this)`

### Recommendations

- Add `clearSecrets()` method to `NewResult` class
- Add security warning to `toStrings()` docstring
```
