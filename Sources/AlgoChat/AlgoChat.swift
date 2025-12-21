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

    // MARK: - Sending Messages

    /// Sends an encrypted message to a recipient
    ///
    /// - Parameters:
    ///   - message: The plaintext message (max ~962 bytes when UTF-8 encoded)
    ///   - recipient: The recipient's Algorand address
    ///   - recipientPublicKey: Optional cached public key (will be fetched if not provided)
    /// - Returns: The transaction ID
    /// - Throws: `ChatError.messageTooLarge` if message exceeds size limit
    public func send(
        message: String,
        to recipient: Address,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey? = nil
    ) async throws -> String {
        // Get recipient's encryption public key
        let pubKey: Curve25519.KeyAgreement.PublicKey
        if let provided = recipientPublicKey {
            pubKey = provided
        } else {
            pubKey = try await fetchPublicKey(for: recipient)
        }

        // Encrypt the message
        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: pubKey
        )

        // Get transaction parameters
        let params = try await algokit.algodClient.transactionParams()

        // Create and sign the transaction
        let signedTx = try MessageTransaction.createSigned(
            from: account,
            to: recipient,
            envelope: envelope,
            params: params
        )

        // Submit transaction
        return try await algokit.algodClient.sendTransaction(signedTx)
    }

    /// Sends a message and waits for confirmation
    ///
    /// - Parameters:
    ///   - message: The plaintext message
    ///   - recipient: The recipient's Algorand address
    ///   - recipientPublicKey: Optional cached public key (will be fetched if not provided)
    ///   - timeout: Maximum rounds to wait (default: 10)
    /// - Returns: The transaction ID
    public func sendAndWait(
        message: String,
        to recipient: Address,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey? = nil,
        timeout: UInt64 = 10
    ) async throws -> String {
        let txid = try await send(message: message, to: recipient, recipientPublicKey: recipientPublicKey)
        _ = try await algokit.algodClient.waitForConfirmation(
            transactionID: txid,
            timeout: timeout
        )
        return txid
    }

    // MARK: - Fetching Messages

    /// Fetches messages from a conversation
    ///
    /// - Parameters:
    ///   - participant: The other party in the conversation
    ///   - afterRound: Only fetch messages after this round (for pagination)
    ///   - limit: Maximum number of messages to fetch
    /// - Returns: Array of decrypted messages, sorted chronologically
    public func fetchMessages(
        with participant: Address,
        afterRound: UInt64? = nil,
        limit: Int = 50
    ) async throws -> [Message] {
        try await indexer.fetchMessages(
            with: participant,
            afterRound: afterRound,
            limit: limit
        )
    }

    /// Fetches all conversations for the current account
    ///
    /// - Parameter limit: Maximum number of transactions to scan
    /// - Returns: Array of conversations, sorted by most recent message
    public func fetchConversations(limit: Int = 100) async throws -> [Conversation] {
        try await indexer.fetchConversations(limit: limit)
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
