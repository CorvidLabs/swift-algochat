---
change: CHG-0004-cover-the-codex-agent-integration-during-hosted-pull-request-validation
artifact: plan
---

# Plan

1. Record `.codex/skills/spec-sync/SKILL.md` as the sole affected path.
2. Align the Codex pre-PR instruction with the committed 100% coverage policy.
3. Re-run strict SpecSync validation and the native Trust gate.
4. Push the active change and require exact-head hosted Trust and CodeQL checks to pass.
