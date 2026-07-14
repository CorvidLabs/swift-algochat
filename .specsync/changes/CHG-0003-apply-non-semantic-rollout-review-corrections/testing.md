---
change: CHG-0003-apply-non-semantic-rollout-review-corrections
artifact: testing
---

# Testing

- `REQ-algochat-012`: the Fledge lane must pass the 68-test cryptographic batch, the 169-test unit and envelope-security batch, and the noninteractive CLI product build.
- `REQ-algochat-002`, `REQ-algochat-003`, and `REQ-algochat-007`: the added fourteen tests cover envelope round trips, truncation, key substitution, tampered wrapped keys, third-party resistance, wrong PSKs, wrong counters, and bidirectional decryption.
- `specsync check --strict --require-coverage 100 --force` must pass all 36 files and 279 exports.
- `specsync agents status` must report Claude, Cursor, Codex, and Gemini installed after command corrections.
- `fledge trust doctor` and `fledge trust verify` must pass with progressive provenance.
- Diff review must show no changes under `Sources/`, `Tests/`, `Package.swift`, or dependency locks.
