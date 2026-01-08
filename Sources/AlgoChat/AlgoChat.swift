import Algorand
import AlgoKit
@preconcurrency import Crypto
import Foundation

/**
 Main entry point for the AlgoChat library

 AlgoChat enables encrypted peer-to-peer messaging using the Algorand blockchain.
 Messages are stored as encrypted transaction notes, ensuring:
 - Immutability: Messages are permanently recorded on-chain
 - Decentralization: No central server controls message delivery
 - Privacy: End-to-end encryption using Curve25519 key agreement

 ## Getting Started

 ```swift
 // Create a chat client
 let chat = try await AlgoChat(
     network: .testnet,
     account: myAccount
 )

 // Send an encrypted message
 let txid = try await chat.send(
     message: "Hello, Algorand!",
     to: recipientAddress
 )

 // Fetch messages from a conversation
 let messages = try await chat.fetchMessages(with: recipientAddress)
 ```
 */
public actor AlgoChat {
    // MARK: - Constants

    /// Minimum transaction fee in microAlgos
    private static let minTransactionFee: UInt64 = 1000

    /// Minimum account balance in microAlgos (to avoid account closure)
    private static let minAccountBalance: UInt64 = 100_000

    // MARK: - Properties

    /// The underlying AlgoKit client
    public let algokit: AlgoKit

    /// The chat-enabled account
    public let account: ChatAccount

    /// The message indexer for fetching messages
    private let indexer: MessageIndexer

    /// Optional message cache for offline access
    private let messageCache: (any MessageCache)?

    /// Public key cache for reducing blockchain lookups
    private let publicKeyCache: PublicKeyCache

    // MARK: - Initialization

    /**
     Creates a new AlgoChat client

     - Parameters:
       - network: The Algorand network to connect to
       - account: The Algorand account to use for chat
       - messageCache: Optional message cache for offline access
       - publicKeyCache: Optional public key cache (default: in-memory with 24h TTL)
     */
    public init(
        network: AlgorandConfiguration.Network,
        account: Account,
        messageCache: (any MessageCache)? = nil,
        publicKeyCache: PublicKeyCache? = nil
    ) async throws {
        self.algokit = AlgoKit(network: network)
        self.account = try ChatAccount(account: account)
        self.messageCache = messageCache
        self.publicKeyCache = publicKeyCache ?? PublicKeyCache()

        guard let indexerClient = await algokit.indexerClient else {
            throw ChatError.indexerNotConfigured
        }

        self.indexer = MessageIndexer(
            indexerClient: indexerClient,
            chatAccount: self.account
        )
    }

    /**
     Creates a new AlgoChat client with custom configuration

     - Parameters:
       - configuration: Custom Algorand configuration
       - account: The Algorand account to use for chat
       - messageCache: Optional message cache for offline access
       - publicKeyCache: Optional public key cache (default: in-memory with 24h TTL)
     */
    public init(
        configuration: AlgorandConfiguration,
        account: Account,
        messageCache: (any MessageCache)? = nil,
        publicKeyCache: PublicKeyCache? = nil
    ) async throws {
        self.algokit = AlgoKit(configuration: configuration)
        self.account = try ChatAccount(account: account)
        self.messageCache = messageCache
        self.publicKeyCache = publicKeyCache ?? PublicKeyCache()

        guard let indexerClient = await algokit.indexerClient else {
            throw ChatError.indexerNotConfigured
        }

        self.indexer = MessageIndexer(
            indexerClient: indexerClient,
            chatAccount: self.account
        )
    }

    // MARK: - Conversations

    /**
     Gets or creates a conversation with a participant

     This is the primary entry point for messaging. The returned conversation
     can be used with `send(_:to:options:)` to send messages.

     - Parameter participant: The other party's Algorand address
     - Returns: A conversation object (may be empty if no history exists)
     */
    public func conversation(with participant: Address) async throws -> Conversation {
        var conv = Conversation(participant: participant)

        // Try to get the participant's encryption key
        if participant == account.address {
            conv.participantEncryptionKey = account.encryptionPublicKey
        } else if let pubKey = try? await fetchPublicKey(for: participant) {
            conv.participantEncryptionKey = pubKey
        }

        return conv
    }

    /**
     Fetches all conversations for the current account

     - Parameter limit: Maximum number of transactions to scan
     - Returns: Array of conversations, sorted by most recent message
     */
    public func conversations(limit: Int = 100) async throws -> [Conversation] {
        try await indexer.fetchConversations(limit: limit)
    }

    /**
     Refreshes a conversation with the latest messages from the blockchain

     This method uses incremental sync - it only fetches messages after the
     last known round, reducing blockchain queries. Messages are also cached
     locally if a message cache is configured.

     - Parameters:
       - conversation: The conversation to refresh
       - limit: Maximum number of messages to fetch
     - Returns: Updated conversation with new messages merged in
     */
    public func refresh(
        _ conversation: Conversation,
        limit: Int = 50
    ) async throws -> Conversation {
        var updated = conversation

        // Determine starting round for incremental sync
        var afterRound = conversation.lastFetchedRound
        if afterRound == nil, let cache = messageCache {
            afterRound = try? await cache.getLastSyncRound(for: conversation.participant)
        }

        let messages = try await indexer.fetchMessages(
            with: conversation.participant,
            afterRound: afterRound,
            limit: limit
        )

        updated.merge(messages)

        if let lastRound = messages.map({ $0.confirmedRound }).max() {
            updated.lastFetchedRound = lastRound

            // Cache the new messages
            if let cache = messageCache, !messages.isEmpty {
                try? await cache.store(messages, for: conversation.participant)
                try? await cache.setLastSyncRound(lastRound, for: conversation.participant)
            }
        }

        // Update public key if we found it from received messages
        if updated.participantEncryptionKey == nil,
           messages.contains(where: { $0.direction == .received }) {
            updated.participantEncryptionKey = try? await fetchPublicKey(for: conversation.participant)
        }

        return updated
    }

    /**
     Loads cached messages for a conversation (offline access)

     - Parameter participant: The conversation participant
     - Returns: Cached messages, or empty array if no cache or cache miss
     */
    public func loadCached(for participant: Address) async -> [Message] {
        guard let cache = messageCache else { return [] }
        return (try? await cache.retrieve(for: participant, afterRound: nil)) ?? []
    }

    /**
     Loads older messages from the blockchain (backward pagination)

     Use this to load message history before the oldest message in the conversation.

     - Parameters:
       - conversation: The conversation to load older messages for
       - limit: Maximum number of messages to fetch
     - Returns: Updated conversation with older messages merged in
     */
    public func loadOlder(
        _ conversation: Conversation,
        limit: Int = 50
    ) async throws -> Conversation {
        var updated = conversation

        // Find the oldest message's round to paginate backwards
        let oldestRound = conversation.messages
            .map { $0.confirmedRound }
            .filter { $0 > 0 }
            .min()

        // Fetch messages before the oldest round
        let messages = try await indexer.fetchMessages(
            with: conversation.participant,
            beforeRound: oldestRound.map { $0 - 1 },  // -1 to exclude current oldest
            limit: limit
        )

        updated.merge(messages)

        // Update public key if we found it from received messages
        if updated.participantEncryptionKey == nil,
           messages.contains(where: { $0.direction == .received }) {
            updated.participantEncryptionKey = try? await fetchPublicKey(for: conversation.participant)
        }

        return updated
    }

    // MARK: - Sending Messages

    /**
     Sends a message to a conversation

     This is the primary send method. Use `SendOptions` to configure
     confirmation waiting and reply context.

     - Parameters:
       - message: The plaintext message (max ~962 bytes when UTF-8 encoded)
       - conversation: The conversation to send to
       - options: Send options (default: fire-and-forget)
     - Returns: SendResult containing the transaction ID and sent message

     Example usage:
     ```swift
     // Simple send
     let result = try await chat.send("Hello!", to: conversation)

     // Send and wait for confirmation, then update locally
     let result = try await chat.send("Hello!", to: conversation, options: .confirmed)
     conversation.append(result.message)

     // Send a reply
     if let lastMsg = conversation.lastReceived {
         let result = try await chat.send(
             "Thanks!",
             to: conversation,
             options: .replying(to: lastMsg, confirmed: true)
         )
     }
     ```
     */
    @discardableResult
    public func send(
        _ message: String,
        to conversation: Conversation,
        options: SendOptions = .default
    ) async throws -> SendResult {
        // Validate message size before encryption
        let messageBytes = Data(message.utf8)
        let maxSize = ChatEnvelope.maxPayloadSize
        if messageBytes.count > maxSize {
            throw ChatError.messageTooLarge(maxSize: maxSize)
        }

        // Check balance before proceeding
        let currentBalance = try await balance()
        let requiredBalance = Self.minTransactionFee + Self.minAccountBalance
        if currentBalance.value < requiredBalance {
            throw ChatError.insufficientBalance(
                required: requiredBalance,
                available: currentBalance.value
            )
        }

        // Get recipient's encryption public key
        let pubKey: Curve25519.KeyAgreement.PublicKey
        if let cached = conversation.participantEncryptionKey {
            pubKey = cached
        } else if conversation.participant == account.address {
            pubKey = account.encryptionPublicKey
        } else {
            pubKey = try await fetchPublicKey(for: conversation.participant)
        }

        // Encrypt the message
        let envelope: ChatEnvelope
        if let replyContext = options.replyContext {
            envelope = try MessageEncryptor.encrypt(
                message: message,
                replyTo: (txid: replyContext.messageId, preview: replyContext.preview),
                senderPrivateKey: account.encryptionPrivateKey,
                recipientPublicKey: pubKey
            )
        } else {
            envelope = try MessageEncryptor.encrypt(
                message: message,
                senderPrivateKey: account.encryptionPrivateKey,
                recipientPublicKey: pubKey
            )
        }

        // Get transaction parameters
        let params = try await algokit.algodClient.transactionParams()

        // Create and sign the transaction
        let signedTx = try MessageTransaction.createSigned(
            from: account,
            to: conversation.participant,
            envelope: envelope,
            params: params
        )

        // Submit transaction
        let txid = try await algokit.algodClient.sendTransaction(signedTx)

        // Wait for confirmation if requested and get round info
        var confirmedRound: UInt64 = 0
        let timestamp = Date()

        if options.waitForConfirmation {
            let confirmation = try await algokit.algodClient.waitForConfirmation(
                transactionID: txid,
                timeout: options.timeout
            )
            confirmedRound = confirmation.confirmedRound ?? 0
            // Use current time as timestamp (close enough for display purposes)
        }

        // Wait for indexer if requested (ensures message is visible when fetching)
        if options.waitForIndexer {
            _ = await indexer.waitForTransaction(txid, timeout: options.indexerTimeout)
        }

        // Build the sent message for optimistic local update
        let sentMessage = Message(
            id: txid,
            sender: account.address,
            recipient: conversation.participant,
            content: message,
            timestamp: timestamp,
            confirmedRound: confirmedRound,
            direction: .sent,
            replyContext: options.replyContext
        )

        return SendResult(txid: txid, message: sentMessage)
    }

    /// Sends a message to an address (convenience for one-off messages)
    ///
    /// For persistent messaging, use `conversation(with:)` and `send(_:to:options:)`.
    @discardableResult
    public func send(
        _ message: String,
        to recipient: Address,
        options: SendOptions = .default
    ) async throws -> SendResult {
        let conv = try await conversation(with: recipient)
        return try await send(message, to: conv, options: options)
    }

    // MARK: - Key Management

    /// Returns the account's encryption public key (for sharing with others)
    public var publicKey: Data {
        account.publicKeyData
    }

    /**
     Fetches a user's encryption public key from their past transactions

     This first checks the local cache, then scans the user's transaction
     history to find a previous AlgoChat message and extracts the sender's
     public key from the envelope.

     - Parameter address: The user's Algorand address
     - Returns: Their X25519 public key
     - Throws: `ChatError.publicKeyNotFound` if no chat history exists
     */
    public func fetchPublicKey(
        for address: Address
    ) async throws -> Curve25519.KeyAgreement.PublicKey {
        // Check cache first
        if let cachedData = await publicKeyCache.retrieve(for: address),
           let cached = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: cachedData) {
            return cached
        }

        // Fetch from blockchain
        let discovered = try await indexer.findPublicKey(for: address)

        // Cache for future lookups
        await publicKeyCache.store(discovered.publicKey.rawRepresentation, for: address)

        return discovered.publicKey
    }

    /**
     Discovers a user's encryption public key with verification status

     Unlike `fetchPublicKey`, this method returns whether the key was
     cryptographically verified via a V3 signed envelope.

     - Parameter address: The user's Algorand address
     - Returns: The discovered key with verification status
     - Throws: `ChatError.publicKeyNotFound` if no chat history exists
     */
    public func discoverKey(
        for address: Address
    ) async throws -> DiscoveredKey {
        try await indexer.findPublicKey(for: address)
    }

    /**
     Publishes the account's encryption public key to the blockchain

     This creates a zero-value self-payment transaction containing the
     encryption public key, allowing other users to discover it and send
     encrypted messages without needing to receive a message first.

     The key is signed with the account's Ed25519 key (V3 envelope) to prove
     ownership and prevent key substitution attacks.

     The key-publish transaction is automatically filtered from the
     conversation list.

     - Returns: The transaction ID
     */
    public func publishKey() async throws -> String {
        // Create key-publish payload
        let payload = KeyPublishPayload()
        let payloadData = try JSONEncoder().encode(payload)

        // Encrypt with our own key (self-encryption)
        let envelope = try MessageEncryptor.encryptRaw(
            payloadData,
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )

        // Get transaction parameters
        let params = try await algokit.algodClient.transactionParams()

        // Create zero-value self-payment (just publishes the key in the note)
        let signedTx = try MessageTransaction.createSigned(
            from: account,
            to: account.address,
            envelope: envelope,
            params: params,
            amount: MicroAlgos(0)
        )

        // Submit transaction
        return try await algokit.algodClient.sendTransaction(signedTx)
    }

    /**
     Publishes the key and waits for confirmation

     - Parameter timeout: Maximum rounds to wait (default: 10)
     - Returns: The transaction ID
     */
    public func publishKeyAndWait(timeout: UInt64 = 10) async throws -> String {
        let txid = try await publishKey()
        _ = try await algokit.algodClient.waitForConfirmation(
            transactionID: txid,
            timeout: timeout
        )
        return txid
    }

    // MARK: - Account Info

    /// The current account's Algorand address
    public var address: Address {
        account.address
    }

    /// Fetches the current account balance
    public func balance() async throws -> MicroAlgos {
        let info = try await algokit.algodClient.accountInformation(account.address)
        return MicroAlgos(info.amount)
    }

    // MARK: - Cache Management

    /// Clears all cached data (messages and public keys)
    public func clearCache() async throws {
        try await messageCache?.clear()
        await publicKeyCache.clear()
    }

    /**
     Clears cached data for a specific conversation

     - Parameter participant: The conversation participant
     */
    public func clearCache(for participant: Address) async throws {
        try await messageCache?.clear(for: participant)
        await publicKeyCache.invalidate(for: participant)
    }

    /**
     Invalidates a cached public key

     Use this if you suspect a cached key is stale or invalid.

     - Parameter address: The address to invalidate
     */
    public func invalidateCachedPublicKey(for address: Address) async {
        await publicKeyCache.invalidate(for: address)
    }
}
