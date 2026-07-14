---
change: CHG-0002-establish-complete-canonical-swift-algochat-contract-coverage
artifact: requirements
---

# Requirements

This migration establishes `REQ-algochat-001` through `REQ-algochat-012` as the stable identifiers for the existing package contract. Their normative text is recorded in `deltas/algochat.md` and will be applied to `specs/algochat/requirements.md` on acceptance.

No implementation behavior is added or removed. Every identifier maps to an existing deterministic build or test surface, and environment-dependent LocalNet behavior is explicitly separated from the native gate.
