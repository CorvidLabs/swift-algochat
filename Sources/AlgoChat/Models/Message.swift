import Algorand
import Foundation

/// A chat message between Algorand addresses
public struct Message: Sendable, Identifiable, Codable {
    /// Unique identifier (transaction ID)
    public let id: String

    /// Sender's Algorand address
    public let sender: Address

    /// Recipient's Algorand address
    public let recipient: Address

    /// Decrypted message content
    public let content: String

    /// Timestamp when the message was confirmed on-chain
    public let timestamp: Date

    /// The round in which the transaction was confirmed
    public let confirmedRound: UInt64

    /// Direction relative to the current user
    public enum Direction: String, Sendable, Codable {
        case sent
        case received
    }

    /// Message direction
    public let direction: Direction

    /// Transaction ID this message replies to (nil if not a reply)
    public let replyToId: String?

    /// Preview of the original message being replied to
    public let replyToPreview: String?

    public init(
        id: String,
        sender: Address,
        recipient: Address,
        content: String,
        timestamp: Date,
        confirmedRound: UInt64,
        direction: Direction,
        replyToId: String? = nil,
        replyToPreview: String? = nil
    ) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.content = content
        self.timestamp = timestamp
        self.confirmedRound = confirmedRound
        self.direction = direction
        self.replyToId = replyToId
        self.replyToPreview = replyToPreview
    }

    /// Whether this message is a reply to another message
    public var isReply: Bool {
        replyToId != nil
    }
}

extension Message: Equatable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

extension Message: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
