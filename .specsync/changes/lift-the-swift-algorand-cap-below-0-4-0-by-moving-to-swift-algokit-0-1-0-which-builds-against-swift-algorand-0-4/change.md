---
id: lift-the-swift-algorand-cap-below-0-4-0-by-moving-to-swift-algokit-0-1-0-which-builds-against-swift-algorand-0-4
state: draft
type: bug_fix
base_commit: 5aa7214e241a6a3fb7215960efa2ffac46ddeae0
---

# Lift the swift-algorand cap below 0.4.0 by moving to swift-algokit 0.1.0, which builds against swift-algorand 0.4

## Intent

Lift the swift-algorand cap below 0.4.0 by moving to swift-algokit 0.1.0, which builds against swift-algorand 0.4

## Affected Canonical Specs

- `algochat`

## Acceptance Criteria

- swift-algochat resolves and builds against swift-algorand 0.4 through swift-algokit 0.1.0; the non-localnet test suite passes; AlgoChat's public API is unchanged.

## No-spec Rationale

AlgoChat's public API is unchanged: its initializers already throw, and only dependency bounds and internal try expressions change.
