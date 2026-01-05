import Algorand
import Foundation

/**
 A message that is queued for sending

 Pending messages are stored when the app is offline or when a send fails.
 They can be retried when connectivity is restored.
 */
public struct PendingMessage: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier for this pending message
    public let id: UUID

    /// The recipient's Algorand address
    public let recipient: Address

    /// The plaintext message content
    public let content: String

    /// Optional reply context if this is a reply
    public let replyContext: ReplyContext?

    /// When the message was created
    public let createdAt: Date

    /// Number of times sending has been attempted
    public var retryCount: Int

    /// When the last send attempt occurred
    public var lastAttempt: Date?

    /// Current status of the pending message
    public var status: Status

    /// Error from the last failed attempt
    public var lastError: String?

    /// Status of a pending message
    public enum Status: String, Codable, Sendable {
        /// Waiting to be sent
        case pending

        /// Currently being sent
        case sending

        /// Send failed (may be retried)
        case failed

        /// Successfully sent (should be removed from queue)
        case sent
    }

    /// Creates a new pending message
    public init(
        id: UUID = UUID(),
        recipient: Address,
        content: String,
        replyContext: ReplyContext? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastAttempt: Date? = nil,
        status: Status = .pending,
        lastError: String? = nil
    ) {
        self.id = id
        self.recipient = recipient
        self.content = content
        self.replyContext = replyContext
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastAttempt = lastAttempt
        self.status = status
        self.lastError = lastError
    }

    /// Returns a copy marked as sending
    public func markSending() -> PendingMessage {
        var copy = self
        copy.status = .sending
        copy.lastAttempt = Date()
        return copy
    }

    /// Returns a copy marked as failed with the given error
    public func markFailed(error: String) -> PendingMessage {
        var copy = self
        copy.status = .failed
        copy.retryCount += 1
        copy.lastError = error
        return copy
    }

    /// Returns a copy marked as sent
    public func markSent() -> PendingMessage {
        var copy = self
        copy.status = .sent
        return copy
    }

    /// Whether this message can be retried
    public func canRetry(maxRetries: Int) -> Bool {
        status == .failed && retryCount < maxRetries
    }
}

// MARK: - Codable for Address

extension PendingMessage {
    private enum CodingKeys: String, CodingKey {
        case id, recipient, content, replyContext, createdAt
        case retryCount, lastAttempt, status, lastError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let recipientString = try container.decode(String.self, forKey: .recipient)
        recipient = try Address(string: recipientString)
        content = try container.decode(String.self, forKey: .content)
        replyContext = try container.decodeIfPresent(ReplyContext.self, forKey: .replyContext)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        lastAttempt = try container.decodeIfPresent(Date.self, forKey: .lastAttempt)
        status = try container.decode(Status.self, forKey: .status)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recipient.description, forKey: .recipient)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(replyContext, forKey: .replyContext)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(lastAttempt, forKey: .lastAttempt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }
}
