# swift-algochat

[![macOS](https://img.shields.io/github/actions/workflow/status/CorvidLabs/swift-algochat/macOS.yml?label=macOS&branch=main)](https://github.com/CorvidLabs/swift-algochat/actions/workflows/macOS.yml)
[![Linux](https://img.shields.io/github/actions/workflow/status/CorvidLabs/swift-algochat/linux.yml?label=Linux&branch=main)](https://github.com/CorvidLabs/swift-algochat/actions/workflows/linux.yml)
[![License](https://img.shields.io/github/license/CorvidLabs/swift-algochat)](https://github.com/CorvidLabs/swift-algochat/blob/main/LICENSE)
[![Version](https://img.shields.io/github/v/release/CorvidLabs/swift-algochat)](https://github.com/CorvidLabs/swift-algochat/releases)

> **Pre-1.0 Notice**: This library is under active development. The API may change between minor versions until 1.0.

> **Security Notice**: This library has not been independently audited. While it uses well-established cryptographic primitives from [swift-crypto](https://github.com/apple/swift-crypto), use in production is at your own risk.

Encrypted peer-to-peer messaging on the Algorand blockchain. Built with Swift 6 and async/await.

## Features

- **End-to-End Encryption** - X25519 key agreement + ChaCha20-Poly1305
- **Forward Secrecy** - Per-message ephemeral keys protect past messages
- **Immutable Messages** - Permanently recorded on-chain
- **Decentralized** - No central server controls delivery
- **Bidirectional Decryption** - Both sender and recipient can decrypt messages
- **Reply Support** - Thread conversations with reply context
- **Biometric Storage** - Protect encryption keys with Face ID / Touch ID
- **Multi-Platform** - iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+, Linux

## Installation

### Swift Package Manager

Add AlgoChat to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/CorvidLabs/swift-algochat.git", from: "0.1.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "AlgoChat", package: "swift-algochat")
    ]
)
```

Or add it via Xcode:
1. File > Add Package Dependencies
2. Enter: `https://github.com/CorvidLabs/swift-algochat.git`

## Quick Start

### Creating a Chat Client

```swift
import AlgoChat
import Algorand

// Create a new account
let account = try Account()

// Initialize chat client
let chat = try await AlgoChat(network: .testnet, account: account)
```

### Sending Messages

```swift
// Start a conversation
let recipient = try Address(string: "RECIPIENT_ADDRESS_HERE")
let conversation = try await chat.conversation(with: recipient)

// Send a message (wait for confirmation)
try await chat.send("Hello!", to: conversation, options: .confirmed)

// Send with indexer confirmation (guarantees visibility on refresh)
try await chat.send("Hello!", to: conversation, options: .indexed)

// Send a reply
if let lastMessage = conversation.lastReceived {
    try await chat.send("Thanks!", to: conversation, options: .replying(to: lastMessage))
}
```

### Fetching Messages

```swift
// Get all conversations
let conversations = try await chat.conversations()

// Refresh a specific conversation
let updated = try await chat.refresh(conversation)

// Access messages
for message in updated.messages {
    print("\(message.direction): \(message.content)")
}

// Filter by direction
let received = updated.receivedMessages
let sent = updated.sentMessages
```

### Publishing Your Key

Allow others to message you before you've sent them a message:

```swift
try await chat.publishKeyAndWait()
```

## Core Concepts

### Encryption

Messages are encrypted using modern cryptographic primitives:

- **Key Agreement**: X25519 elliptic curve Diffie-Hellman
- **Encryption**: ChaCha20-Poly1305 authenticated encryption
- **Key Derivation**: HKDF-SHA256 with domain separation
- **Forward Secrecy**: Fresh ephemeral key per message

### Message Envelope Format (v1)

```
[version: 1][protocol: 1][sender_pubkey: 32][ephemeral_pubkey: 32][nonce: 12][encrypted_sender_key: 48][ciphertext: variable]
```

- **Header size**: 126 bytes
- **Maximum message**: 882 bytes (after encryption overhead)

### Key Storage

```swift
// Biometric-protected storage (Apple platforms)
let storage = KeychainKeyStorage()
let chatAccount = try await ChatAccount(account: algorandAccount, storage: storage)

// Password-encrypted file storage (Linux/cross-platform)
let storage = FileKeyStorage(directory: ".algochat", password: "secret")
```

### Send Options

```swift
// Fire-and-forget (fastest)
try await chat.send("Hello!", to: conversation)

// Wait for blockchain confirmation
try await chat.send("Hello!", to: conversation, options: .confirmed)

// Wait for indexer (guarantees visibility)
try await chat.send("Hello!", to: conversation, options: .indexed)
```

## CLI Tool

The package includes an interactive command-line interface:

```bash
swift run algochat
```

## Testing

### Unit Tests

```bash
swift test
```

### Integration Tests (LocalNet)

```bash
# Start local Algorand network
algokit localnet start

# Run integration tests
swift test --filter "LocalnetIntegration"

# Stop localnet
algokit localnet stop
```

## Requirements

- Swift 6.0+
- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+ / visionOS 1.0+
- Linux (with Swift 6.0+)
- [AlgoKit CLI](https://github.com/algorandfoundation/algokit-cli) (optional, for localnet testing)

## Security

See [SECURITY.md](SECURITY.md) for:
- Cryptographic guarantees
- Threat model
- Key management details

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Resources

- [swift-algorand](https://github.com/CorvidLabs/swift-algorand) - Algorand SDK for Swift
- [swift-algokit](https://github.com/CorvidLabs/swift-algokit) - High-level Algorand toolkit
- [Algorand Developer Portal](https://developer.algorand.org)
