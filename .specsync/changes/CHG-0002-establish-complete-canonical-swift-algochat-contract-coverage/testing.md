---
change: CHG-0002-establish-complete-canonical-swift-algochat-contract-coverage
artifact: testing
---

# Testing

- `REQ-algochat-001`: `swift build -v` and the CLI product build prove the Swift 6 library/executable package boundary and strict-concurrency compilation.
- `REQ-algochat-002`: the cryptographic batch covers standard envelope encoding, decoding, lengths, versions, protocols, and invalid framing.
- `REQ-algochat-003`: the cryptographic batch covers ephemeral agreement, key derivation, signing, authenticated encryption, tamper rejection, and sender decryption.
- `REQ-algochat-004`: the unit batch covers messages, conversations, reply context, payload encoding, formatting, direction, and backward-compatible decoding.
- `REQ-algochat-005`: the unit batch covers transaction creation, configured amounts, key-publication filtering, indexer paging, discovery, and wait behavior with deterministic adapters.
- `REQ-algochat-006`: the cryptographic/model tests cover PSK contacts and exchange URI creation, parsing, round trips, and invalid input.
- `REQ-algochat-007`: the cryptographic batch covers PSK envelope framing, counter byte order, hybrid authenticated encryption, limits, and tamper rejection.
- `REQ-algochat-008`: the cryptographic batch covers ratchet derivation, send advancement, replay detection, receive windows, two-phase recording, pruning, and manager persistence.
- `REQ-algochat-009`: the unit batch covers pending state transitions, persistence, queue ordering, retry limits, removal, clearing, and permanent failure.
- `REQ-algochat-010`: the unit batch covers online state, synchronization, pending selection, cache de-duplication, last-sync rounds, pagination, and invalidation.
- `REQ-algochat-011`: storage tests cover in-memory, file, PSK, and platform key storage behavior, round trips, deletion, corruption, password handling, and unsupported capabilities.
- `REQ-algochat-012`: the Fledge lane passes 68 cryptographic tests plus 155 remaining unit tests and the CLI help smoke test; strict SpecSync and Trust commands provide governance evidence.

LocalNet integration remains environment-dependent evidence for `REQ-algochat-005` and is not claimed as executed by this migration change.
