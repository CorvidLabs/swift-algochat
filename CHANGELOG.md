# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- **Real PBKDF2 key derivation** - `FileKeyStorage` now performs genuine
  PBKDF2-HMAC-SHA256 at 100,000 iterations (CommonCrypto on Apple platforms,
  RFC 8018 HMAC-SHA256 on Linux). The previous implementation looped SHA-256
  and a single HKDF pass, which was not PBKDF2 and was not interoperable with
  the reference implementations. Key files keep the 92-byte format
  (salt 32 + nonce 12 + ciphertext 32 + tag 16).
- **Cryptographically secure randomness at rest** - `FileKeyStorage` salt and
  nonce generation now use the explicit platform CSPRNG path
  (`SecRandomCopyBytes` / `/dev/urandom`) and surface a thrown error instead of
  trapping when secure randomness is unavailable.
- **Signature-verified key discovery** - Key discovery verifies appended
  Ed25519 signatures over the announced X25519 key against the sender's
  Algorand address and reports the actual verification result; unsigned or
  invalid announcements are reported as unverified instead of trusted.
- **Envelope fields safe to index** - `ChatEnvelope` and `PSKEnvelope` now
  store zero-indexed `Data` for every field. CryptoKit sealed-box outputs and
  `Data` slice concatenation can carry a non-zero `startIndex`, which made
  integer subscripting (e.g. `envelope.ciphertext[0]`) trap. Fields are
  re-based on construction so indexing untrusted envelope data cannot crash.

### Changed
- CI runs the full test suite on macOS and Linux (the previous `--filter`
  expressions skipped the PSK, signature-verifier and file-key-storage
  suites). Localnet integration suites self-skip when localnet is unavailable.

### Added
- Tag-triggered release workflow that builds, tests, and publishes a GitHub
  release.
- PBKDF2-HMAC-SHA256 known-answer test vectors.

## [0.3.0] - 2026-01-27

### Added
- **PSK messaging protocol v1.1** - Pre-shared key conversations with a
  ratcheting counter for forward secrecy and replay protection.

## [0.2.0] - 2026-01-24

### Added
- **Custom payment amount** - Optional custom microAlgo amount when sending
  messages.

## [0.1.3] - 2026-01-08

### Fixed
- Use the Application Support directory for key storage on iOS.

## [0.1.2] - 2026-01-07

### Added
- Backward pagination for loading older messages.

### Fixed
- Restored `decryptSent` and simplified sender-side decryption so sent
  messages decrypt correctly when loaded from the blockchain.

## [0.1.1] - 2026-01-07

### Fixed
- Sent messages could not be decrypted when loaded from the blockchain.

## [0.1.0] - 2026-01-05

Initial public release.

### Added
- **Core messaging** - Send and receive encrypted messages on Algorand blockchain
- **End-to-end encryption** - X25519 key agreement + ChaCha20-Poly1305
- **Forward secrecy** - Per-message ephemeral keys protect past messages
- **Bidirectional decryption** - Both sender and recipient can decrypt messages
- **Reply support** - Thread conversations with reply context
- **Conversation management** - Track messages by participant
- **Key discovery** - Automatic public key lookup from transaction history
- **Public key publishing** - Announce encryption key via self-transaction
- **Biometric key storage** - Keychain integration with Face ID / Touch ID
- **File-based key storage** - Password-encrypted storage for Linux/non-Apple platforms
- **Message caching** - In-memory and file-based cache implementations
- **Send queue** - Persistent queue for offline message delivery
- **CLI tool** - Interactive command-line interface for testing

### Security
- Envelope format v1 with ephemeral keys and encrypted sender key
- HKDF key derivation with domain separation
- Secure random generation via platform APIs
- No force unwraps or unsafe operations in library code

### Platforms
- macOS 12+
- iOS 15+
- tvOS 15+
- watchOS 8+
- visionOS 1+
- Linux (via swift-crypto)

### Notes
- This is envelope format **v1** - the first public wire format

### Dependencies
- swift-algokit 0.0.2+
- swift-crypto 3.0.0+
- swift-cli 0.1.0+ (CLI only)
