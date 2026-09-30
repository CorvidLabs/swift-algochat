---
change: lift-the-swift-algorand-cap-below-0-4-0-by-moving-to-swift-algokit-0-1-0-which-builds-against-swift-algorand-0-4
artifact: context
---

# Context

swift-algochat caps swift-algorand at `"0.2.0" ..< "0.4.0"` because swift-algokit 0.0.2 did not
compile against swift-algorand 0.4.0's throwing configuration factories. That cap stops any app
already on swift-algorand 0.4 from using AlgoChat. corvid-bot needs AlgoChat for holder voting
(corvid-bot #210), and Leif chose to fix this upstream (2026-09-30).

CorvidLabs/swift-algokit#20 makes `AlgoKit(network:)` throw and builds against swift-algorand 0.3
and 0.4. It is to be released as swift-algokit 0.1.0. This change moves swift-algochat onto it
and drops the cap.

**Until swift-algokit 0.1.0 is tagged**, this branch depends on swift-algokit's
`fix/swift-algorand-0.4` branch. Before merge it must switch to `from: "0.1.0"`.
