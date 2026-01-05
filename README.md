# AlgoChat

Encrypted peer-to-peer messaging on the Algorand blockchain.

## Features

- **End-to-End Encryption** - X25519 key agreement + ChaCha20-Poly1305
- **Immutable Messages** - Permanently recorded on-chain
- **Decentralized** - No central server controls delivery
- **Reply Support** - Thread conversations with reply context
- **Biometric Storage** - Protect encryption keys with Face ID / Touch ID
- **Self-Messaging** - Send notes to yourself

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/CorvidLabs/swift-algochat.git", from: "0.1.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["AlgoChat"]
)
```

## Quick Start

```swift
import AlgoChat
import Algorand

// Create a chat client
let account = try Account()
let chat = try await AlgoChat(network: .testnet, account: account)

// Start a conversation
let recipient = try Address(string: "ABC123...")
let conversation = try await chat.conversation(with: recipient)

// Send a message
let result = try await chat.send("Hello!", to: conversation, options: .confirmed)

// Fetch messages
let updated = try await chat.refresh(conversation)
for message in updated.messages {
    print("\(message.direction): \(message.content)")
}
```

## Usage

### Sending Messages

```swift
// Simple send (fire-and-forget)
try await chat.send("Hello!", to: conversation)

// Wait for blockchain confirmation
try await chat.send("Hello!", to: conversation, options: .confirmed)

// Wait for indexer (guarantees visibility on refresh)
try await chat.send("Hello!", to: conversation, options: .indexed)

// Send a reply
if let lastMessage = conversation.lastReceived {
    try await chat.send("Thanks!", to: conversation, options: .replying(to: lastMessage))
}
```

### Fetching Conversations

```swift
// Get all conversations
let conversations = try await chat.conversations()

// Refresh a specific conversation
let updated = try await chat.refresh(conversation)

// Access messages
let received = updated.receivedMessages
let sent = updated.sentMessages
let last = updated.lastMessage
```

### Publishing Your Key

Allow others to message you before you've sent them a message:

```swift
try await chat.publishKeyAndWait()
```

### Biometric Key Storage

Protect encryption keys with Face ID / Touch ID:

```swift
let storage = KeychainKeyStorage()
let account = try await ChatAccount(account: algorandAccount, storage: storage)
```

## CLI Demo

Try the interactive CLI:

```bash
swift run algochat
```

## Requirements

- Swift 6.0+
- macOS 12+ / iOS 15+ / visionOS 1+
- [AlgoKit](https://github.com/algorandfoundation/algokit-cli) for local development

## Running Tests

```bash
# Unit tests
swift test

# Integration tests (requires localnet)
algokit localnet start
swift test --filter "LocalnetIntegration"
```

## How It Works

1. **Key Derivation** - X25519 encryption keys derived from Algorand account via HKDF
2. **Encryption** - Messages encrypted with recipient's public key using ChaCha20-Poly1305
3. **Storage** - Encrypted payload stored in transaction note field
4. **Discovery** - Public keys discovered by scanning sender's transaction history

### Message Envelope Format (v4)

```
[version: 1 byte][protocol: 1 byte][sender_pubkey: 32 bytes][ephemeral_pubkey: 32 bytes][nonce: 12 bytes][encrypted_sender_key: 48 bytes][ciphertext+tag: variable]
```

- **Header size:** 126 bytes
- **Maximum message size:** 882 bytes (after encryption overhead)
- **Forward secrecy:** Ephemeral keys provide per-message forward secrecy
- **Bidirectional decryption:** Both sender and recipient can decrypt messages

## License

MIT
