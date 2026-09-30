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
and 0.4. It was released as swift-algokit 0.1.0 (2502d3a). This change moves swift-algochat to
`from: "0.1.0"` and drops the cap.
