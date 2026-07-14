---
change: CHG-0004-cover-the-codex-agent-integration-during-hosted-pull-request-validation
artifact: context
---

# Context

Hosted Trust correctly rejected the exact PR range because the Codex integration file is meaningful but was omitted from the affected-path inventory of the accepted review change. The product sources and tests are unchanged; this follow-up keeps the Codex guidance under an active, auditable change until hosted validation completes.
