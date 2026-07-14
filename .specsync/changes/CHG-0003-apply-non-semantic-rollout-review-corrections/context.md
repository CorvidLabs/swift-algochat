---
change: CHG-0003-apply-non-semantic-rollout-review-corrections
artifact: context
---

# Context

Review found five concrete gaps in the governance-only rollout: the Trust lane omitted fourteen existing envelope-security tests; its `--help` invocation entered an interactive CLI that has no argument parser; governance and agent policy files were absent from meaningful-path enforcement; Gemini's create-change prompt referenced an unsupported argument variable; and the create-spec prompts treated the first word of prose as a module name.

The corrections change verification and agent configuration only. They do not modify package sources, tests, public APIs, wire behavior, dependencies, or release workflows.
