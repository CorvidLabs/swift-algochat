---
spec: algochat.spec.md
---

## Key Decisions

- Standard mode prioritizes interoperable forward secrecy through per-message X25519 ephemeral keys and authenticated encryption.
- PSK mode is optional defense-in-depth. It adds a deterministic ratchet and replay window without replacing authenticated ECDH.
- Transaction notes are the immutable transport; the indexer is the read/discovery plane and local caches are accelerators, not authorities.
- Durable queues and platform-specific key storage sit behind async `Sendable` protocols so applications can substitute implementations.

## Files to Read First

- `Sources/AlgoChat/AlgoChat.swift` for client orchestration.
- `Sources/AlgoChat/Models/ChatEnvelope.swift` and `PSKEnvelope.swift` for wire formats.
- `Sources/AlgoChat/Crypto/MessageEncryptor.swift` and `PSKRatchet.swift` for cryptographic behavior.
- `Sources/AlgoChat/Blockchain/MessageTransaction.swift` and `MessageIndexer.swift` for transport and discovery.
- `Sources/AlgoChat/Queue/SendQueue.swift` and `SyncManager.swift` for offline delivery.

## Current Status

The implemented package builds under Swift 6. Its deterministic verification lane passes 68 cryptographic tests, 155 other unit tests, and a CLI smoke test. LocalNet integration remains an explicit environment-dependent workflow rather than part of this migration gate.

## Operational Notes

The project is pre-1.0 and not independently audited. Consumers should treat key material, PSKs, transaction permanence, and public-chain metadata according to the threat model in `SECURITY.md`.
