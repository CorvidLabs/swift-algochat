---
spec: algochat.spec.md
---

# Requirements

These normative requirements define the accepted contract for the implemented package.

### REQ-algochat-001

The package SHALL expose the Swift 6 `AlgoChat` library and `algochat` executable with strict concurrency enabled, async client operations, actor isolation for shared mutable state, and the declared Apple and Linux platform support.

#### Acceptance Criteria

- Package manifest exports `AlgoChat` and `algochat` with Swift 6 strict-concurrency settings.
- The deterministic build and CLI smoke test succeed on the supported runner.

### REQ-algochat-002

Standard envelopes SHALL encode version `0x01` and protocol `0x01`, validate the 32-byte static and ephemeral public keys, 12-byte nonce, 48-byte wrapped sender key, 126-byte header, and 1,024-byte note ceiling, and reject unsupported or truncated data.

#### Acceptance Criteria

- Standard envelope round trips preserve every field and reject invalid version, protocol, size, or length.
- Encoded standard notes remain within 1,024 bytes.

### REQ-algochat-003

Standard message cryptography SHALL use fresh X25519 ephemeral agreement, HKDF-SHA256 domain separation, ChaCha20-Poly1305 authenticated encryption, signed identity binding, and sender-key wrapping so either participant can authenticate and decrypt authorized content.

#### Acceptance Criteria

- Both authorized participants decrypt valid standard messages and tampering fails authentication.
- Fresh ephemeral keys and signature verification are covered by deterministic cryptographic tests.

### REQ-algochat-004

Messages and conversations SHALL preserve transaction identity, sender, recipient, content, timestamp, confirmed round, direction, protocol mode, and optional reply context; reply previews must be limited to 80 characters and plain-text payloads must remain decodable.

#### Acceptance Criteria

- Message and conversation round trips retain identity, direction, protocol, and reply metadata.
- Reply previews do not exceed 80 characters and legacy plain text remains readable.

### REQ-algochat-005

Blockchain integration SHALL create and sign payment transactions containing valid note payloads, default to 1,000 microAlgos unless overridden, publish discoverable public-key metadata, page indexer searches, filter key-publication records, and optionally wait for confirmation and indexer visibility.

#### Acceptance Criteria

- Transaction construction honors default and custom payment amounts without exceeding note limits.
- Indexer tests cover paging, key discovery, publication filtering, confirmation, and visibility waits.

### REQ-algochat-006

PSK exchange URIs and contacts SHALL round-trip a valid Algorand address, exactly 32 bytes of pre-shared key material, and an optional label; malformed schemes, versions, addresses, keys, and persisted contacts must be rejected.

#### Acceptance Criteria

- Valid PSK URIs round-trip address, 32-byte key, and optional label.
- Malformed scheme, version, address, or key material is rejected.

### REQ-algochat-007

PSK envelopes SHALL use protocol `0x02`, encode a big-endian 32-bit counter in a 130-byte header, combine ratcheted PSK material with ephemeral ECDH, enforce the 1,024-byte note ceiling, and authenticate before exposing plaintext.

#### Acceptance Criteria

- PSK envelope round trips preserve its counter and fields while respecting the note ceiling.
- Tampering, invalid framing, or incorrect key material fails before plaintext is exposed.

### REQ-algochat-008

PSK state and management SHALL derive deterministic session and position keys, advance send counters, reject reused or out-of-window receive counters, record counters only after successful decryption, prune obsolete replay state, and persist contacts and state through `PSKStorage`.

#### Acceptance Criteria

- Send counters advance deterministically and receive counters are recorded only after authentication.
- Replays and out-of-window counters fail, and obsolete replay entries are pruned.

### REQ-algochat-009

The send queue SHALL persist pending messages and their retry state, provide deterministic enqueue/dequeue/remove/clear operations, retry only within the configured limit, remove successful sends, and surface permanent failures without falsely reporting delivery.

#### Acceptance Criteria

- Pending messages and retry state survive storage round trips.
- Successful messages are removed; exhausted messages report permanent failure without false delivery.

### REQ-algochat-010

Synchronization and caching SHALL distinguish online and syncing state, process queued work when a client is available, cache messages by participant without duplicates, preserve last-sync rounds, support pagination and conversation refresh, and permit scoped or complete invalidation.

#### Acceptance Criteria

- Cache and synchronization tests preserve online/syncing state, message uniqueness, and last-sync rounds.
- Scoped and complete invalidation plus pagination behave deterministically.

### REQ-algochat-011

Key and PSK storage SHALL preserve private key confidentiality and durable state: Apple platforms use Keychain and optional biometric controls, cross-platform file storage uses authenticated password-based protection where configured, and storage errors must not silently replace or disclose key material.

#### Acceptance Criteria

- Key/contact/state storage round trips and deletion succeed for available implementations.
- Corruption, invalid passwords, and unsupported platform capability return errors without disclosing key material.

### REQ-algochat-012

Verification SHALL build the owned library target and CLI product, run the 68-test cryptographic batch and 169-test unit and envelope-security batch, validate every governed source file and exported symbol at 100% SpecSync coverage, and make no semantic changes to `Sources/` or `Tests/` during this migration.

#### Acceptance Criteria

- The Fledge lane passes 68 cryptographic tests, 169 other unit and envelope-security tests, and the noninteractive CLI product build.
- SpecSync strict coverage and quality score are 100%, with no changes under `Sources/` or `Tests/`.
