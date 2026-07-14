---
module: algochat
version: 4
status: active
files:
  - Sources/AlgoChat/AlgoChat.swift
  - Sources/AlgoChat/Blockchain/MessageIndexer.swift
  - Sources/AlgoChat/Blockchain/MessageTransaction.swift
  - Sources/AlgoChat/Crypto/EphemeralKeyManager.swift
  - Sources/AlgoChat/Crypto/KeyDerivation.swift
  - Sources/AlgoChat/Crypto/MessageEncryptor.swift
  - Sources/AlgoChat/Crypto/PSKRatchet.swift
  - Sources/AlgoChat/Crypto/SignatureVerifier.swift
  - Sources/AlgoChat/Errors/ChatError.swift
  - Sources/AlgoChat/Models/ChatAccount.swift
  - Sources/AlgoChat/Models/ChatEnvelope.swift
  - Sources/AlgoChat/Models/Conversation.swift
  - Sources/AlgoChat/Models/DiscoveredKey.swift
  - Sources/AlgoChat/Models/EnvelopeDecoder.swift
  - Sources/AlgoChat/Models/Message.swift
  - Sources/AlgoChat/Models/MessagePayload.swift
  - Sources/AlgoChat/Models/PSKContact.swift
  - Sources/AlgoChat/Models/PSKEnvelope.swift
  - Sources/AlgoChat/Models/PSKExchangeURI.swift
  - Sources/AlgoChat/Models/PSKState.swift
  - Sources/AlgoChat/Models/SendOptions.swift
  - Sources/AlgoChat/PSK/PSKManager.swift
  - Sources/AlgoChat/Queue/FileSendQueueStorage.swift
  - Sources/AlgoChat/Queue/PendingMessage.swift
  - Sources/AlgoChat/Queue/SendQueue.swift
  - Sources/AlgoChat/Queue/SyncManager.swift
  - Sources/AlgoChat/Storage/EncryptionKeyStorage.swift
  - Sources/AlgoChat/Storage/FileKeyStorage.swift
  - Sources/AlgoChat/Storage/FilePSKStorage.swift
  - Sources/AlgoChat/Storage/InMemoryMessageCache.swift
  - Sources/AlgoChat/Storage/KeychainKeyStorage.swift
  - Sources/AlgoChat/Storage/MessageCache.swift
  - Sources/AlgoChat/Storage/PSKStorage.swift
  - Sources/AlgoChat/Storage/PublicKeyCache.swift
  - Sources/AlgoChat/Storage/StorageDirectory.swift
  - Sources/AlgoChatCLI/AlgoChatCLI.swift
db_tables: []
depends_on: []
---

# AlgoChat

## Purpose

Provide a Swift 6, async/await API and CLI for encrypted peer-to-peer messages carried in Algorand payment transaction notes. The library owns standard and PSK wire envelopes, encryption and signing, blockchain publication and discovery, conversation models, durable queues, synchronization, and platform-appropriate local key and contact storage.

The package is pre-1.0 and has not received an independent security audit. Its public cryptographic behavior remains interoperable with the other AlgoChat language implementations.

## Public API

The contract includes every public declaration exported by the `AlgoChat` library and the `algochat` executable entry point. The exact symbol inventory below is generated from the implemented Swift sources and reviewed with this specification.

### Exported Symbols

| Symbol |
|--------|
| `AlgoChat` |
| `algokit` |
| `account` |
| `pskManager` |
| `conversation` |
| `conversations` |
| `refresh` |
| `loadCached` |
| `loadOlder` |
| `send` |
| `publicKey` |
| `fetchPublicKey` |
| `discoverKey` |
| `publishKey` |
| `publishKeyAndWait` |
| `address` |
| `balance` |
| `clearCache` |
| `invalidateCachedPublicKey` |
| `addPSKContact` |
| `removePSKContact` |
| `hasPSKContact` |
| `pskContacts` |
| `generatePSKExchangeURI` |
| `sendPSK` |
| `init` |
| `TransactionSearching` |
| `searchTransactions` |
| `MessageIndexer` |
| `defaultPageSize` |
| `fetchMessages` |
| `fetchConversations` |
| `defaultDiscoveryPageSize` |
| `findPublicKey` |
| `waitForTransaction` |
| `extractKey` |
| `MessageTransaction` |
| `minimumPayment` |
| `create` |
| `createSigned` |
| `createSignedKeyPublish` |
| `EphemeralKeyManager` |
| `generateKeyPair` |
| `deriveEncryptionKey` |
| `deriveDecryptionKey` |
| `KeyDerivation` |
| `deriveEncryptionKeys` |
| `encodePublicKey` |
| `decodePublicKey` |
| `MessageEncryptor` |
| `encrypt` |
| `encryptRaw` |
| `decrypt` |
| `encryptPSK` |
| `decryptPSK` |
| `PSKRatchet` |
| `deriveSessionPSK` |
| `derivePositionPSK` |
| `derivePSKAtCounter` |
| `deriveHybridSymmetricKey` |
| `deriveSenderKey` |
| `SignatureVerifier` |
| `signatureSize` |
| `sign` |
| `verify` |
| `fingerprint` |
| `ChatError` |
| `errorDescription` |
| `messageTooLarge` |
| `decryptionFailed` |
| `encodingFailed` |
| `randomGenerationFailed` |
| `invalidPublicKey` |
| `keyDerivationFailed` |
| `invalidSignature` |
| `invalidEnvelope` |
| `unsupportedVersion` |
| `unsupportedProtocol` |
| `indexerNotConfigured` |
| `publicKeyNotFound` |
| `invalidRecipient` |
| `transactionFailed` |
| `insufficientBalance` |
| `pskNotFound` |
| `pskCounterOutOfRange` |
| `pskCounterReplay` |
| `ChatAccount` |
| `encryptionPublicKey` |
| `saveEncryptionKey` |
| `hasStoredEncryptionKey` |
| `deleteStoredEncryptionKey` |
| `publicKeyData` |
| `description` |
| `ChatEnvelope` |
| `version` |
| `protocolID` |
| `headerSize` |
| `encryptedSenderKeySize` |
| `tagSize` |
| `maxPayloadSize` |
| `senderPublicKey` |
| `ephemeralPublicKey` |
| `encryptedSenderKey` |
| `nonce` |
| `ciphertext` |
| `encode` |
| `decode` |
| `Conversation` |
| `id` |
| `participant` |
| `participantEncryptionKey` |
| `lastFetchedRound` |
| `lastMessage` |
| `lastReceived` |
| `lastSent` |
| `receivedMessages` |
| `sentMessages` |
| `messageCount` |
| `isEmpty` |
| `append` |
| `merge` |
| `DiscoveredKey` |
| `isVerified` |
| `EnvelopeDecoder` |
| `DecodedEnvelope` |
| `isChatMessage` |
| `standard` |
| `psk` |
| `ReplyContext` |
| `messageId` |
| `preview` |
| `Message` |
| `sender` |
| `recipient` |
| `content` |
| `timestamp` |
| `confirmedRound` |
| `Direction` |
| `direction` |
| `replyContext` |
| `ProtocolMode` |
| `protocolMode` |
| `isReply` |
| `==` |
| `hash` |
| `sent` |
| `received` |
| `DecryptedContent` |
| `text` |
| `replyToId` |
| `replyToPreview` |
| `formattedContent` |
| `PSKContact` |
| `initialPSK` |
| `label` |
| `createdAt` |
| `PSKEnvelope` |
| `ratchetCounter` |
| `PSKExchangeURI` |
| `toString` |
| `parse` |
| `PSKState` |
| `sessionSize` |
| `counterWindow` |
| `sendCounter` |
| `peerLastCounter` |
| `seenCounters` |
| `validateCounter` |
| `recordReceive` |
| `validateAndRecordReceive` |
| `advanceSendCounter` |
| `SendResult` |
| `txid` |
| `message` |
| `SendOptions` |
| `waitForConfirmation` |
| `timeout` |
| `waitForIndexer` |
| `indexerTimeout` |
| `amount` |
| `confirmed` |
| `indexed` |
| `replying` |
| `withAmount` |
| `PSKManager` |
| `addContact` |
| `removeContact` |
| `hasContact` |
| `getContact` |
| `nextSendCounter` |
| `validateAndDerivePSK` |
| `listContacts` |
| `FileSendQueueStorage` |
| `save` |
| `load` |
| `PendingMessage` |
| `retryCount` |
| `lastAttempt` |
| `status` |
| `lastError` |
| `Status` |
| `markSending` |
| `markFailed` |
| `markSent` |
| `canRetry` |
| `pending` |
| `sending` |
| `failed` |
| `SendQueueStorage` |
| `SendQueue` |
| `onPermanentFailure` |
| `enqueue` |
| `dequeue` |
| `getPending` |
| `remove` |
| `clear` |
| `count` |
| `InMemorySendQueueStorage` |
| `SyncManager` |
| `onMessageSent` |
| `onMessageFailed` |
| `onConnectivityChange` |
| `setOnline` |
| `online` |
| `syncIfNeeded` |
| `sync` |
| `queueMessage` |
| `pendingMessages` |
| `retry` |
| `syncing` |
| `EncryptionKeyStorage` |
| `KeyStorageError` |
| `store` |
| `retrieve` |
| `hasKey` |
| `delete` |
| `listStoredAddresses` |
| `keyNotFound` |
| `storageFailed` |
| `retrievalFailed` |
| `biometricNotAvailable` |
| `biometricFailed` |
| `invalidKeyData` |
| `passwordRequired` |
| `directoryNotFound` |
| `FileKeyStorage` |
| `setPassword` |
| `clearPassword` |
| `FilePSKStorage` |
| `storeContact` |
| `retrieveContact` |
| `deleteContact` |
| `storeState` |
| `retrieveState` |
| `InMemoryMessageCache` |
| `getLastSyncRound` |
| `setLastSyncRound` |
| `getCachedConversations` |
| `KeychainKeyStorage` |
| `authenticationPrompt` |
| `isBiometricAvailable` |
| `biometricType` |
| `BiometricType` |
| `none` |
| `touchID` |
| `faceID` |
| `opticID` |
| `MessageCache` |
| `MessageCacheError` |
| `notFound` |
| `PSKStorage` |
| `PublicKeyCacheProtocol` |
| `PublicKeyCache` |
| `ttl` |
| `invalidate` |
| `pruneExpired` |
| `StorageDirectory` |
| `defaultDirectoryName` |
| `resolve` |

## Invariants

1. Standard envelopes use version `0x01`, protocol `0x01`, a 126-byte header, and a 1,024-byte transaction-note ceiling; PSK envelopes use protocol `0x02` and a 130-byte header.
2. Standard encryption combines a fresh X25519 ephemeral key, HKDF-SHA256 domain separation, and ChaCha20-Poly1305; sender-key wrapping permits both participants to decrypt the stored message.
3. PSK mode combines the ratcheted 32-byte pre-shared key with ephemeral ECDH, rejects replayed or out-of-window counters, and records a receive counter only after successful decryption.
4. On-chain message and key-publication transactions use the configured payment amount, never exceeding the Algorand note limit; the default amount is 1,000 microAlgos.
5. Queue, cache, storage, and client state exposed across concurrency boundaries remain actor-isolated or `Sendable`.
6. Key-publish payloads are discovery metadata and are not returned as chat messages.
7. Reply metadata preserves the original transaction identifier and limits its preview to 80 characters while remaining backward-compatible with plain-text payloads.
8. This governance migration changes specifications and verification configuration only; it does not change package source or test behavior.

## Behavioral Examples

### Scenario: Send and retrieve a standard encrypted message

- **Given** a local account and a recipient whose X25519 public key can be discovered
- **When** `AlgoChat.send` creates and submits a message with standard send options
- **Then** the note contains a valid standard envelope, the returned `SendResult` contains the transaction identifier and optimistic message, and indexer refresh reconstructs the conversation

### Scenario: Exchange a ratcheted PSK message

- **Given** both contacts share the same 32-byte PSK and persisted counter state
- **When** the sender advances its counter and sends through `sendPSK`
- **Then** the recipient derives the matching counter key, authenticates and decrypts the envelope, records the counter, and rejects any replay

### Scenario: Continue after temporary send failure

- **Given** a durable pending message and an offline or failing transport
- **When** synchronization resumes
- **Then** the queue retries up to its configured limit, persists each state transition, removes successful entries, and reports permanent failure without reporting a false send

## Error Cases

| Condition | Behavior |
|-----------|----------|
| Envelope version, protocol, length, key length, nonce, or authentication is invalid | Decoding or decryption fails with a typed `ChatError`; unauthenticated content is not emitted |
| Recipient public key cannot be discovered | The send operation fails rather than encrypting to an unknown identity |
| PSK contact is missing, malformed, replayed, or outside its counter window | PSK management throws and does not advance persisted receive state on failed decryption |
| Blockchain submission, confirmation, or indexer visibility times out | The requested send/fetch operation throws or remains queued according to `SendOptions` |
| Key, contact, state, or queue persistence is unavailable or corrupt | The storage implementation returns its documented error and does not silently replace durable state |
| A platform lacks Apple Keychain or biometric APIs | The cross-platform storage implementation reports unsupported behavior; file storage remains available |

## Dependencies

### Consumes

| Module | What is used |
|--------|-------------|
| `swift-algokit` | Algorand clients, accounts, addresses, payment transactions, signing, confirmation, and indexer access |
| `swift-crypto` | X25519 key agreement, ChaCha20-Poly1305, HKDF-SHA256, and cryptographic key material |
| `swift-cli` | Executable command routing and terminal interaction |
| Foundation / Security / LocalAuthentication | Encoding, files, platform keychain access, and optional biometric policy |

### Consumed By

| Module | What is used |
|--------|-------------|
| Swift applications | `AlgoChat` client, models, encryption helpers, queues, storage protocols, and PSK APIs |
| `algochat` executable | Interactive account, conversation, message, and PSK workflows |
| Other AlgoChat implementations | Shared versioned envelope and cryptographic interoperability contract |

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-07-14 | 0xLeif | Establish complete canonical contract coverage for the implemented Swift package |
| 2026-07-14 | SpecSync | Accepted CHG-0002 complete canonical Swift AlgoChat contract coverage |
| 2026-07-14 | SpecSync | Accepted CHG-0003 non-semantic rollout review corrections |
| 2026-07-14 | SpecSync | CHG-0004-cover-the-codex-agent-integration-during-hosted-pull-request-validation: Cover the Codex agent integration during hosted pull-request validation |

## Purpose and Contract Coverage

The canonical module governs every implemented Swift library and CLI source, its complete detected public export surface, and its standard/PSK messaging, blockchain, queue, synchronization, cache, and storage responsibilities.
