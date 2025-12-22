import Algorand
import AlgoKit
import Crypto
import Foundation

/// Main entry point for the AlgoChat library
///
/// AlgoChat enables encrypted peer-to-peer messaging using the Algorand blockchain.
/// Messages are stored as encrypted transaction notes, ensuring:
/// - Immutability: Messages are permanently recorded on-chain
/// - Decentralization: No central server controls message delivery
/// - Privacy: End-to-end encryption using Curve25519 key agreement
///
/// ## Getting Started
///
/// ```swift
/// // Create a chat client
/// let chat = try await AlgoChat(
///     network: .testnet,
///     account: myAccount
/// )
///
/// // Send an encrypted message
/// let txid = try await chat.send(
///     message: "Hello, Algorand!",
///     to: recipientAddress
/// )
///
/// // Fetch messages from a conversation
/// let messages = try await chat.fetchMessages(with: recipientAddress)
/// ```
public actor AlgoChat {
    // MARK: - Properties

    /// The underlying AlgoKit client
    public let algokit: AlgoKit

    /// The chat-enabled account
    public let account: ChatAccount

    /// The message indexer for fetching messages
    private let indexer: MessageIndexer

    // MARK: - Initialization

    /// Creates a new AlgoChat client
    ///
    /// - Parameters:
    ///   - network: The Algorand network to connect to
    ///   - account: The Algorand account to use for chat
    public init(network: AlgorandConfiguration.Network, account: Account) async throws {
        self.algokit = AlgoKit(network: network)
        self.account = try ChatAccount(account: account)

        guard let indexerClient = await algokit.indexerClient else {
            throw ChatError.indexerNotConfigured
        }

        self.indexer = MessageIndexer(
            indexerClient: indexerClient,
            chatAccount: self.account
        )
    }

    /// Creates a new AlgoChat client with custom configuration
    ///
    /// - Parameters:
    ///   - configuration: Custom Algorand configuration
    ///   - account: The Algorand account to use for chat
    public init(configuration: AlgorandConfiguration, account: Account) async throws {
        self.algokit = AlgoKit(configuration: configuration)
        self.account = try ChatAccount(account: account)

        guard let indexerClient = await algokit.indexerClient else {
            throw ChatError.indexerNotConfigured
        }

        self.indexer = MessageIndexer(
            indexerClient: indexerClient,
            chatAccount: self.account
        )
    }

    // MARK: - Conversations

    /// Gets or creates a conversation with a participant
    ///
    /// This is the primary entry point for messaging. The returned conversation
    /// can be used with `send(_:to:options:)` to send messages.
    ///
    /// - Parameter participant: The other party's Algorand address
    /// - Returns: A conversation object (may be empty if no history exists)
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

    /// Fetches all conversations for the current account
    ///
    /// - Parameter limit: Maximum number of transactions to scan
    /// - Returns: Array of conversations, sorted by most recent message
    public func conversations(limit: Int = 100) async throws -> [Conversation] {
        try await indexer.fetchConversations(limit: limit)
    }

    /// Refreshes a conversation with the latest messages from the blockchain
    ///
    /// - Parameters:
    ///   - conversation: The conversation to refresh
    ///   - limit: Maximum number of messages to fetch
    /// - Returns: Updated conversation with new messages merged in
    public func refresh(
        _ conversation: Conversation,
        limit: Int = 50
    ) async throws -> Conversation {
        var updated = conversation

        let messages = try await indexer.fetchMessages(
            with: conversation.participant,
            afterRound: conversation.lastFetchedRound,
            limit: limit
        )

        updated.merge(messages)

        if let lastRound = messages.map({ $0.confirmedRound }).max() {
            updated.lastFetchedRound = lastRound
        }

        // Update public key if we found it from received messages
        if updated.participantEncryptionKey == nil,
           messages.contains(where: { $0.direction == .received }) {
            updated.participantEncryptionKey = try? await fetchPublicKey(for: conversation.participant)
        }

        return updated
    }

    // MARK: - Sending Messages

    /// Sends a message to a conversation
    ///
    /// This is the primary send method. Use `SendOptions` to configure
    /// confirmation waiting and reply context.
    ///
    /// - Parameters:
    ///   - message: The plaintext message (max ~962 bytes when UTF-8 encoded)
    ///   - conversation: The conversation to send to
    ///   - options: Send options (default: fire-and-forget)
    /// - Returns: The transaction ID
    ///
    /// Example usage:
    /// ```swift
    /// // Simple send
    /// let txid = try await chat.send("Hello!", to: conversation)
    ///
    /// // Send and wait for confirmation
    /// let txid = try await chat.send("Hello!", to: conversation, options: .confirmed)
    ///
    /// // Send a reply
    /// if let lastMsg = conversation.lastReceived {
    ///     let txid = try await chat.send(
    ///         "Thanks!",
    ///         to: conversation,
    ///         options: .replying(to: lastMsg, confirmed: true)
    ///     )
    /// }
    /// ```
    @discardableResult
    public func send(
        _ message: String,
        to conversation: Conversation,
        options: SendOptions = .default
    ) async throws -> String {
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

        // Wait for confirmation if requested
        if options.waitForConfirmation {
            _ = try await algokit.algodClient.waitForConfirmation(
                transactionID: txid,
                timeout: options.timeout
            )
        }

        return txid
    }

    /// Sends a message to an address (convenience for one-off messages)
    ///
    /// For persistent messaging, use `conversation(with:)` and `send(_:to:options:)`.
    @discardableResult
    public func send(
        _ message: String,
        to recipient: Address,
        options: SendOptions = .default
    ) async throws -> String {
        let conv = try await conversation(with: recipient)
        return try await send(message, to: conv, options: options)
    }

    // MARK: - Key Management

    /// Returns the account's encryption public key (for sharing with others)
    public var publicKey: Data {
        account.publicKeyData
    }

    /// Fetches a user's encryption public key from their past transactions
    ///
    /// This scans the user's transaction history to find a previous AlgoChat
    /// message and extracts the sender's public key from the envelope.
    ///
    /// - Parameter address: The user's Algorand address
    /// - Returns: Their X25519 public key
    /// - Throws: `ChatError.publicKeyNotFound` if no chat history exists
    public func fetchPublicKey(
        for address: Address
    ) async throws -> Curve25519.KeyAgreement.PublicKey {
        try await indexer.findPublicKey(for: address)
    }

    /// Publishes the account's encryption public key to the blockchain
    ///
    /// This creates a zero-value self-payment transaction containing the
    /// encryption public key, allowing other users to discover it and send
    /// encrypted messages without needing to receive a message first.
    ///
    /// The key-publish transaction is automatically filtered from the
    /// conversation list.
    ///
    /// - Returns: The transaction ID
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

    /// Publishes the key and waits for confirmation
    ///
    /// - Parameter timeout: Maximum rounds to wait (default: 10)
    /// - Returns: The transaction ID
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
}
