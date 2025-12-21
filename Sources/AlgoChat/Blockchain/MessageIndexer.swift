import Algorand
import AlgoKit
import Crypto
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

        // Sort by most recent message
        return Array(conversationsByAddress.values)
            .sorted { ($0.lastMessage?.timestamp ?? .distantPast) > ($1.lastMessage?.timestamp ?? .distantPast) }
    }

    /// Finds a user's encryption public key from their past transactions
    public func findPublicKey(for address: Address) async throws -> Curve25519.KeyAgreement.PublicKey {
        let response = try await indexerClient.searchTransactions(
            address: address,
            limit: 100
        )

        for tx in response.transactions {
            guard tx.sender == address.description,
                  let noteData = tx.noteData,
                  isChatMessage(noteData) else {
                continue
            }

            let envelope = try ChatEnvelope.decode(from: noteData)
            return try KeyDerivation.decodePublicKey(from: envelope.senderPublicKey)
        }

        throw ChatError.publicKeyNotFound(address.description)
    }

    // MARK: - Private

    private func isChatMessage(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == ChatEnvelope.version && data[1] == ChatEnvelope.protocolID
    }

    private func parseMessage(
        from tx: IndexerTransaction,
        direction: Message.Direction
    ) throws -> Message {
        guard let noteData = tx.noteData else {
            throw ChatError.invalidEnvelope("No note data")
        }

        let envelope = try ChatEnvelope.decode(from: noteData)

        // Decrypt the message
        let content = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: chatAccount.encryptionPrivateKey
        )

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

        return Message(
            id: tx.id,
            sender: sender,
            recipient: recipient,
            content: content,
            timestamp: timestamp,
            confirmedRound: tx.confirmedRound ?? 0,
            direction: direction
        )
    }
}
