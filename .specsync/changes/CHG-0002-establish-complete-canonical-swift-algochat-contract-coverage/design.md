---
change: CHG-0002-establish-complete-canonical-swift-algochat-contract-coverage
artifact: design
---

# Design

One active `algochat` module companion owns the entire package because the public client composes its models, wire formats, cryptography, blockchain transport, persistence, and synchronization as one interoperability contract. Exact source paths prevent false coverage from unsupported glob expansion.

Twelve requirements divide the implemented behavior into package/concurrency, standard framing, standard cryptography, message models, blockchain transport, PSK exchange, PSK framing, ratchet state, queueing, synchronization/cache, storage security, and deterministic verification. Each identifier is stable and appears in both the canonical requirements companion and the change delta.

Trust raises contract coverage from advisory zero to 100 while retaining blocking risk, progressive provenance, disabled Trust-managed Atlas publication, and the Fledge lane. The lane builds the owned library target and package CLI separately so transitive dependency examples cannot create false failures. This preserves product behavior and changes only governance and verification configuration.
