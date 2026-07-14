---
change: CHG-0004-cover-the-codex-agent-integration-during-hosted-pull-request-validation
artifact: testing
---

# Testing

| Verification | Expected evidence | Contract |
|---|---|---|
| `specsync check --strict --require-coverage 100 --force` | All 36 canonical files and 279 exports pass | REQ-algochat-012 |
| `specsync agents status` | Claude, Cursor, Codex, and Gemini report installed | REQ-algochat-012 |
| `fledge trust verify` | The 68-test cryptographic batch, 169-test unit batch, CLI build, SDD, risk, and progressive provenance checks pass | REQ-algochat-012 |
| Exact-head hosted Trust and CodeQL | Both required checks pass before promotion or merge | REQ-algochat-012 |
| Diff review | No changes under `Sources/`, `Tests/`, `Package.swift`, or dependency locks | REQ-algochat-012 |
