# AlgoChat

Encrypted peer-to-peer messaging on the Algorand blockchain.

## Overview

AlgoChat enables end-to-end encrypted messaging using Algorand transactions. Messages are stored as encrypted notes in payment transactions, providing:

- **Immutability** - Messages permanently recorded on-chain
- **Decentralization** - No central server controls delivery
- **Privacy** - X25519 + ChaCha20-Poly1305 encryption

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AlgoChat                             │
├─────────────────────────────────────────────────────────────┤
│  AlgoChat (actor)           Main entry point                │
│    ├── ChatAccount          Account with encryption keys    │
│    ├── MessageEncryptor     Encrypt/decrypt messages        │
│    ├── MessageTransaction   Build blockchain transactions   │
│    └── MessageIndexer       Query messages from indexer     │
├─────────────────────────────────────────────────────────────┤
│  Storage                                                    │
│    ├── EncryptionKeyStorage Protocol for key storage        │
│    └── KeychainKeyStorage   Biometric-protected storage     │
├─────────────────────────────────────────────────────────────┤
│  Demo App (AlgoChatDemo)    Interactive CLI demo            │
└─────────────────────────────────────────────────────────────┘
```

## Key Files

### Library (`Sources/AlgoChat/`)

| File | Purpose |
|------|---------|
| `AlgoChat.swift` | Main actor - send/receive messages, manage keys |
| `Models/ChatAccount.swift` | Account with derived encryption keys |
| `Models/ChatEnvelope.swift` | Wire format for encrypted messages |
| `Models/Message.swift` | Decrypted message model |
| `Crypto/MessageEncryptor.swift` | X25519 + ChaCha20 encryption |
| `Crypto/KeyDerivation.swift` | Derive encryption keys from Algorand account |
| `Blockchain/MessageTransaction.swift` | Create signed transactions |
| `Blockchain/MessageIndexer.swift` | Query messages from indexer |
| `Storage/EncryptionKeyStorage.swift` | Protocol for key storage |
| `Storage/KeychainKeyStorage.swift` | Keychain with biometric protection |

### Demo (`Sources/AlgoChatDemo/`)

| File | Purpose |
|------|---------|
| `AlgoChatDemo.swift` | Interactive CLI using swift-cli |

### Tests (`Tests/AlgoChatTests/`)

| File | Purpose |
|------|---------|
| `AlgoChatTests.swift` | Unit tests for encryption, envelopes |
| `LocalnetIntegrationTests.swift` | End-to-end tests on localnet |
| `KeyStorageTests.swift` | Key storage tests |

## Common Tasks

### Build
```bash
swift build
```

### Run Demo
```bash
swift run algochat-demo
```

### Run Tests
```bash
# All tests
swift test

# Just unit tests (fast)
swift test --filter "ChatEnvelope\|MessageEncryptor\|KeyDerivation\|KeyStorage"

# Integration tests (requires localnet)
algokit localnet start
swift test --filter "LocalnetIntegration"
algokit localnet stop
```

### Start Localnet
```bash
algokit localnet start   # Start
algokit localnet status  # Check status
algokit localnet stop    # Stop
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `swift-algokit` (CorvidLabs) | Algorand blockchain client |
| `swift-algorand` (CorvidLabs) | Low-level Algorand types |
| `swift-crypto` (Apple) | X25519, ChaCha20-Poly1305, HKDF |
| `swift-cli` (CorvidLabs) | Terminal UI for demo |

## Code Patterns

### Actors for Thread Safety
`AlgoChat`, `MessageIndexer`, `KeychainKeyStorage` are all actors.

### Encryption Flow
1. Derive X25519 keys from Algorand account via HKDF
2. Key agreement: sender_private + recipient_public → shared_secret
3. HKDF: shared_secret → symmetric_key
4. ChaCha20-Poly1305: plaintext → ciphertext

### Message Envelope Format
```
[version: 1 byte][protocol: 1 byte][sender_pubkey: 32 bytes][nonce: 12 bytes][ciphertext+tag: variable]
```

### Key Discovery
Public keys are discovered by scanning a user's sent transactions for the `sender_pubkey` in their message envelopes.

## Platform Support

| Platform | Status |
|----------|--------|
| macOS 12+ | Full support (Touch ID) |
| iOS 15+ | Full support (Face ID/Touch ID) |
| visionOS | Full support (Optic ID) |
| tvOS/watchOS | Limited (no biometric) |
