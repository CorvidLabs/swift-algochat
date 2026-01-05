# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Envelope format v4 with ephemeral keys and encrypted sender key
- HKDF key derivation with domain separation
- Secure random generation via platform APIs
- No force unwraps or unsafe operations in library code

### Platforms
- macOS 14+ (library compatible with 12+)
- iOS 17+ (library compatible with 15+)
- tvOS 17+
- watchOS 10+
- visionOS 1+
- Linux (via swift-crypto)

### Notes
- This is envelope format **v4** - the first public wire format
- Prior internal versions (v1-v3) were development iterations and are not supported

### Dependencies
- swift-algokit 0.0.2+
- swift-crypto 3.0.0+
- swift-cli 0.1.0+ (CLI only)
