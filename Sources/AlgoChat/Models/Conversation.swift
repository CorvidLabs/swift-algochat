import Algorand
import Crypto
import Foundation

/// A conversation between two Algorand addresses
public struct Conversation: Sendable, Identifiable {
    /// Unique identifier (the other party's address)
    public var id: String { participant.description }

    /// The other party in the conversation
    public let participant: Address

    /// Cached encryption public key for the participant
    public var participantEncryptionKey: Curve25519.KeyAgreement.PublicKey?

    /// Messages in chronological order
    public private(set) var messages: [Message]

    /// The round of the last fetched message (for pagination)
    public var lastFetchedRound: UInt64?

    // MARK: - Message Access

    /// The most recent message in the conversation
    public var lastMessage: Message? { messages.last }

    /// The most recent received message (for replying)
    public var lastReceived: Message? {
        messages.last { $0.direction == .received }
    }

    /// The most recent sent message
    public var lastSent: Message? {
        messages.last { $0.direction == .sent }
    }

    /// All received messages
    public var receivedMessages: [Message] {
        messages.filter { $0.direction == .received }
    }

    /// All sent messages
    public var sentMessages: [Message] {
        messages.filter { $0.direction == .sent }
    }

    /// Number of messages in the conversation
    public var messageCount: Int { messages.count }

    /// Whether the conversation has any messages
    public var isEmpty: Bool { messages.isEmpty }

    public init(
        participant: Address,
        participantEncryptionKey: Curve25519.KeyAgreement.PublicKey? = nil,
        messages: [Message] = []
    ) {
        self.participant = participant
        self.participantEncryptionKey = participantEncryptionKey
        self.messages = messages
    }

    /// Adds a new message to the conversation
    public mutating func append(_ message: Message) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        messages.sort { $0.timestamp < $1.timestamp }
    }

    /// Merges new messages into the conversation
    public mutating func merge(_ newMessages: [Message]) {
        for message in newMessages {
            append(message)
        }
    }
}
