---
change: lift-the-swift-algorand-cap-below-0-4-0-by-moving-to-swift-algokit-0-1-0-which-builds-against-swift-algorand-0-4
artifact: tasks
---

# Tasks

- [x] Drop the swift-algorand cap; depend on the swift-algokit fix
- [x] `try` on `AlgoKit(network:)`, the CLI's `AlgorandConfiguration`, and the tests' `.localnet()`
- [x] Switch to swift-algokit `from: "0.1.0"` (released at 2502d3a)
- [ ] Definition approval (Leif), check, accept, archive; release afterwards (Leif's go)
