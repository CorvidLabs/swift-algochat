---
change: CHG-0004-cover-the-codex-agent-integration-during-hosted-pull-request-validation
spec: algochat
---

# AlgoChat Codex Governance Delta

## MODIFIED

### REQUIREMENT REQ-algochat-012

Verification SHALL build the owned library target and CLI product, run the 68-test cryptographic batch and 169-test unit and envelope-security batch, validate every governed source file and exported symbol at 100% SpecSync coverage, require the Codex integration to invoke the repository's strict 100% coverage command, and make no semantic changes to `Sources/` or `Tests/` during this migration.

#### Acceptance Criteria

- The Fledge lane passes 68 cryptographic tests, 169 other unit and envelope-security tests, and the noninteractive CLI product build.
- The Codex SpecSync skill invokes `specsync check --strict --require-coverage 100 --force` before a PR.
- SpecSync strict coverage and quality score are 100%, with no changes under `Sources/` or `Tests/`.
