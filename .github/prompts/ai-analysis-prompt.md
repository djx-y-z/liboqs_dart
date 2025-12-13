# Task: Analyze liboqs Release Notes

You are analyzing release notes for liboqs (Open Quantum Safe library) to determine how to update our Dart FFI wrapper package.

## Critical Rules

1. **ONLY use information explicitly stated in the release notes below**
2. **DO NOT invent or assume changes not mentioned in the release notes**
3. **If release notes are vague, be conservative** - default to "patch" and "none"
4. **If unsure, say "unclear from release notes"** instead of guessing

## Our Package Context

We maintain a Dart FFI wrapper that:
- Auto-generates bindings via ffigen from C headers
- Wraps structs: `OQS_KEM`, `OQS_SIG`
- Wraps functions: `OQS_KEM_*`, `OQS_SIG_*`, `OQS_randombytes*`
- Exposes KEM algorithms: ML-KEM (Kyber), FrodoKEM, BIKE, HQC, etc.
- Exposes SIG algorithms: ML-DSA (Dilithium), Falcon, SPHINCS+, etc.

## Version Information

- Current liboqs: CURRENT_VERSION
- New liboqs: NEW_VERSION

## Release Notes

```
RELEASE_NOTES_CONTENT
```

## Analysis Steps

Think step by step:

1. **Scan for API changes**: Look for words like "removed", "renamed", "changed signature", "deprecated", "breaking"
2. **Check struct changes**: Any mentions of OQS_KEM or OQS_SIG struct modifications?
3. **Find new algorithms**: Look for "added", "new algorithm", "new KEM", "new signature scheme"
4. **Security items**: Look for "CVE", "vulnerability", "security fix", "side-channel"
5. **Determine impact**: Based on FACTS found, classify the version bump

## Version Bump Rules

- **major**: ONLY if release notes explicitly mention:
  - Struct field changes (added/removed/reordered fields in OQS_KEM or OQS_SIG)
  - Removed algorithms that were previously available
  - Changed function signatures
  - "Breaking change" or "API break" keywords

- **minor**: If release notes mention:
  - New algorithms added
  - New optional functions added
  - New features that don't break existing code

- **patch**: Default for:
  - Bug fixes
  - Performance improvements
  - Documentation updates
  - Internal refactoring
  - Security patches (unless they change API)

## Response Format

Respond with EXACTLY this format (copy the structure precisely):

VERSION_BUMP: [major|minor|patch]
BREAKING_CHANGES: [list specific changes from release notes, or "none"]
NEW_ALGORITHMS: [list algorithm names from release notes, or "none"]
SECURITY_NOTES: [quote security-related items from release notes, or "none"]
BINDING_CHANGES: [yes|no] - [one sentence explanation based on facts]
CHANGELOG_ENTRY:
- [First bullet point - most important change]
- [Second bullet point - if applicable]

## Example Response (for reference)

For a release that adds ML-KEM-1024 and fixes a memory leak:

VERSION_BUMP: minor
BREAKING_CHANGES: none
NEW_ALGORITHMS: ML-KEM-1024
SECURITY_NOTES: none
BINDING_CHANGES: yes - new algorithm requires binding regeneration to expose new OQS_KEM variant
CHANGELOG_ENTRY:
- Added support for ML-KEM-1024 key encapsulation
- Fixed memory leak in signature verification

Now analyze the release notes above and respond:
