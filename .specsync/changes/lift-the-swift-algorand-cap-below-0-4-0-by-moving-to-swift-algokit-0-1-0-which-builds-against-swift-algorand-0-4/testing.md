---
change: lift-the-swift-algorand-cap-below-0-4-0-by-moving-to-swift-algokit-0-1-0-which-builds-against-swift-algorand-0-4
artifact: testing
---

# Testing

`swift test --skip "LocalnetIntegrationTests|CustomAmountIntegrationTests"` passes 339 tests in
48 suites. The run resolves swift-algorand 0.4.0 and swift-algokit `fix/swift-algorand-0.4`. The
two skipped suites need a Docker localnet, and CI skips them too.

## Requirement evidence

| Requirement | Evidence |
|---|---|
| (no spec change) | The build against swift-algorand 0.4.0; the non-localnet suite passes; the public API is unchanged. |
