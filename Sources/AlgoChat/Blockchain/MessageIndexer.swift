import Algorand
import AlgoKit
@preconcurrency import Crypto
import Foundation

/// Queries and retrieves messages from the blockchain
public actor MessageIndexer {
    private let indexerClient: IndexerClient
    private let chatAccount: ChatAccount

    /// Default page size for fetching messages
    public static let defaultPageSize = 50

    public init(indexerClient: IndexerClient, chatAccount: ChatAccount) {
        self.indexerClient = indexerClient
        self.chatAccount = chatAccount
    }

    /// Fetches messages for a conversation
    ///
    /// - Parameters:
    ///   - participant: The other party in the conversation
    ///   - afterRound: Only fetch messages after this round
    ///   - limit: Maximum number of messages to fetch
    /// - Returns: Array of decrypted messages
    public func fetchMessages(
        with participant: Address,
        afterRound: UInt64? = nil,
        limit: Int = defaultPageSize
    ) async throws -> [Message] {
        var allMessages: [Message] = []

        // Fetch transactions involving our account
        let response = try await indexerClient.searchTransactions(
            address: chatAccount.address,
            limit: limit,
            minRound: afterRound
        )

        for tx in response.transactions {
            // Only process payment transactions with notes
            guard tx.txType == "pay",
                  let noteData = tx.noteData,
                  isChatMessage(noteData) else {
                continue
            }

            // Determine direction and filter by participant
            let direction: Message.Direction

            if tx.sender == chatAccount.address.description {
                // We sent this message
                guard let payment = tx.paymentTransaction,
                      payment.receiver == participant.description else {
                    continue
                }
                direction = .sent
            } else {
                // We received this message
                guard tx.sender == participant.description,
                      let payment = tx.paymentTransaction,
                      payment.receiver == chatAccount.address.description else {
                    continue
                }
                direction = .received
            }

            // Try to parse and decrypt the message
            if let message = try? parseMessage(from: tx, direction: direction) {
                allMessages.append(message)
            }
        }

        return allMessages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Fetches all conversations for the current account
    ///
    /// Scans recent transactions to discover all chat participants and their
    /// message history. Conversations are sorted by most recent message.
    ///
    /// - Parameter limit: Maximum number of transactions to scan (default: 100)
    /// - Returns: Array of conversations sorted by most recent activity
    public func fetchConversations(limit: Int = 100) async throws -> [Conversation] {
        let response = try await indexerClient.searchTransactions(
            address: chatAccount.address,
            limit: limit
        )

        var conversationsByAddress: [String: Conversation] = [:]

        for tx in response.transactions {
            guard tx.txType == "pay",
                  let noteData = tx.noteData,
                  isChatMessage(noteData) else {
                continue
            }

            // Determine the other party
            let otherAddress: String
            let direction: Message.Direction

            if tx.sender == chatAccount.address.description {
                guard let payment = tx.paymentTransaction else { continue }
                otherAddress = payment.receiver
                direction = .sent
            } else {
                guard let payment = tx.paymentTransaction,
                      payment.receiver == chatAccount.address.description else {
                    continue
                }
                otherAddress = tx.sender
                direction = .received
            }

            // Parse and add message
            if let message = try? parseMessage(from: tx, direction: direction) {
                if var conversation = conversationsByAddress[otherAddress] {
                    conversation.append(message)
                    conversationsByAddress[otherAddress] = conversation
                } else {
                    let participant = try Address(string: otherAddress)
                    var conversation = Conversation(participant: participant)
                    conversation.append(message)
                    conversationsByAddress[otherAddress] = conversation
                }
            }
        }

        // Filter empty conversations (e.g., self-conversations with only key-publish)
        // and sort by most recent message
        return Array(conversationsByAddress.values)
            .filter { !$0.messages.isEmpty }
            .sorted { ($0.lastMessage?.timestamp ?? .distantPast) > ($1.lastMessage?.timestamp ?? .distantPast) }
    }

    /// Finds a user's encryption public key from their past transactions
    ///
    /// Searches the user's transaction history to find an AlgoChat message
    /// containing their public key. Prefers V3 envelopes with verified signatures
    /// to prevent key substitution attacks.
    ///
    /// - Parameters:
    ///   - address: The user's Algorand address
    ///   - searchDepth: Number of transactions to search (default: 200)
    /// - Returns: The discovered key with verification status
    /// - Throws: `ChatError.publicKeyNotFound` if no chat history exists
    public func findPublicKey(
        for address: Address,
        searchDepth: Int = 200
    ) async throws -> DiscoveredKey {
        // Search with configurable depth
        let response = try await indexerClient.searchTransactions(
            address: address,
            limit: searchDepth
        )

        // First pass: look for V3 envelopes with valid signatures
        for tx in response.transactions {
            guard tx.sender == address.description,
                  let noteData = tx.noteData,
                  isChatMessage(noteData) else {
                continue
            }

            guard let envelope = try? ChatEnvelope.decode(from: noteData) else {
                continue
            }

            // V3 envelopes have signatures - verify before trusting
            if envelope.hasSignature, let signature = envelope.signature {
                let isValid = try SignatureVerifier.verify(
                    encryptionPublicKey: envelope.senderPublicKey,
                    signedBy: address,
                    signature: signature
                )

                if isValid {
                    let publicKey = try KeyDerivation.decodePublicKey(from: envelope.senderPublicKey)
                    return DiscoveredKey(publicKey: publicKey, isVerified: true)
                }
                // Invalid signature - skip this transaction, try next
                continue
            }
        }

        // Second pass: fall back to V1/V2 envelopes (no signature verification)
        // This maintains backward compatibility with older clients
        for tx in response.transactions {
            guard tx.sender == address.description,
                  let noteData = tx.noteData,
                  isChatMessage(noteData) else {
                continue
            }

            guard let envelope = try? ChatEnvelope.decode(from: noteData) else {
                continue
            }

            // Accept V1/V2 envelopes without signature (legacy compatibility)
            if !envelope.hasSignature {
                let publicKey = try KeyDerivation.decodePublicKey(from: envelope.senderPublicKey)
                return DiscoveredKey(publicKey: publicKey, isVerified: false)
            }
        }

        throw ChatError.publicKeyNotFound(address.description)
    }

    /// Polls the indexer until a specific transaction appears
    ///
    /// Uses exponential backoff with jitter to reduce load on the indexer
    /// while still providing timely notification when the transaction appears.
    ///
    /// - Parameters:
    ///   - txid: The transaction ID to wait for
    ///   - timeout: Maximum time to wait in seconds
    ///   - initialInterval: Initial time between polls (default: 0.5 seconds)
    ///   - maxInterval: Maximum time between polls (default: 5.0 seconds)
    ///   - backoffMultiplier: Factor to increase interval each attempt (default: 1.5)
    /// - Returns: true if the transaction was found, false if timeout
    public func waitForTransaction(
        _ txid: String,
        timeout: TimeInterval,
        initialInterval: TimeInterval = 0.5,
        maxInterval: TimeInterval = 5.0,
        backoffMultiplier: Double = 1.5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var currentInterval = initialInterval

        while Date() < deadline {
            // Query indexer for transactions from our account
            do {
                let response = try await indexerClient.searchTransactions(
                    address: chatAccount.address,
                    limit: 50
                )

                // Check if the transaction appears in results
                if response.transactions.contains(where: { $0.id == txid }) {
                    return true
                }
            } catch {
                // Indexer error - keep trying with backoff
            }

            // Exponential backoff with jitter (±20%)
            let jitter = Double.random(in: 0.8...1.2)
            let sleepInterval = currentInterval * jitter
            try? await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))

            // Increase interval for next attempt (capped at maxInterval)
            currentInterval = min(currentInterval * backoffMultiplier, maxInterval)

            // Check for cancellation
            if Task.isCancelled {
                return false
            }
        }

        return false
    }

    // MARK: - Private

    private func isChatMessage(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let version = data[0]
        let validVersion = version == ChatEnvelope.versionV1
            || version == ChatEnvelope.versionV2
            || version == ChatEnvelope.versionV3
        return validVersion && data[1] == ChatEnvelope.protocolID
    }

    private func parseMessage(
        from tx: IndexerTransaction,
        direction: Message.Direction
    ) throws -> Message? {
        guard let noteData = tx.noteData else {
            throw ChatError.invalidEnvelope("No note data")
        }

        let envelope = try ChatEnvelope.decode(from: noteData)

        // Decrypt the message (returns structured content with optional reply metadata)
        // Returns nil for key-publish payloads, which should be filtered out
        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: chatAccount.encryptionPrivateKey
        ) else {
            // Key-publish payload - not a real message
            return nil
        }

        let sender = try Address(string: tx.sender)

        guard let payment = tx.paymentTransaction else {
            throw ChatError.invalidEnvelope("Not a payment transaction")
        }
        let recipient = try Address(string: payment.receiver)

        let timestamp: Date
        if let roundTime = tx.roundTime {
            timestamp = Date(timeIntervalSince1970: TimeInterval(roundTime))
        } else {
            timestamp = Date()
        }

        // Build reply context if this is a reply
        let replyContext: ReplyContext?
        if let replyId = decrypted.replyToId, let preview = decrypted.replyToPreview {
            replyContext = ReplyContext(messageId: replyId, preview: preview)
        } else {
            replyContext = nil
        }

        return Message(
            id: tx.id,
            sender: sender,
            recipient: recipient,
            content: decrypted.text,
            timestamp: timestamp,
            confirmedRound: tx.confirmedRound ?? 0,
            direction: direction,
            replyContext: replyContext
        )
    }
}
