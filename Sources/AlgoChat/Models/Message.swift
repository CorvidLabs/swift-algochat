import Algorand
import Foundation

/// Context for a reply message, linking it to the original
public struct ReplyContext: Sendable, Codable, Equatable, Hashable {
    /// Transaction ID of the original message
    public let messageId: String

    /// Preview of the original message (truncated)
    public let preview: String

    public init(messageId: String, preview: String) {
        self.messageId = messageId
        self.preview = preview
    }

    /// Creates a ReplyContext from a Message
    public init(replyingTo message: Message, maxLength: Int = 80) {
        self.messageId = message.id
        self.preview = message.content.count > maxLength
            ? String(message.content.prefix(maxLength - 3)) + "..."
            : message.content
    }
}

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

    /// Reply context if this message is a reply
    public let replyContext: ReplyContext?

    /// The protocol mode used for this message
    public enum ProtocolMode: String, Sendable, Codable {
        /// Standard mode (protocol 0x01)
        case standard

        /// PSK ratcheting mode (protocol 0x02)
        case psk
    }

    /// The protocol mode used for this message (nil for backward compat)
    public let protocolMode: ProtocolMode?

    public init(
        id: String,
        sender: Address,
        recipient: Address,
        content: String,
        timestamp: Date,
        confirmedRound: UInt64,
        direction: Direction,
        replyContext: ReplyContext? = nil,
        protocolMode: ProtocolMode? = nil
    ) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.content = content
        self.timestamp = timestamp
        self.confirmedRound = confirmedRound
        self.direction = direction
        self.replyContext = replyContext
        self.protocolMode = protocolMode
    }

    /// Whether this message is a reply to another message
    public var isReply: Bool {
        replyContext != nil
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
