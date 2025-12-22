import Algorand
import Foundation

/// Result of sending a message
public struct SendResult: Sendable {
    /// Transaction ID
    public let txid: String

    /// The sent message (for optimistic local updates)
    public let message: Message

    public init(txid: String, message: Message) {
        self.txid = txid
        self.message = message
    }
}

/// Options for sending a message
public struct SendOptions: Sendable {
    /// Whether to wait for transaction confirmation before returning
    public var waitForConfirmation: Bool

    /// Maximum rounds to wait for confirmation (if waitForConfirmation is true)
    public var timeout: UInt64

    /// Whether to wait for the message to appear in the indexer
    /// This ensures the message is visible when fetching conversations
    public var waitForIndexer: Bool

    /// Maximum time (in seconds) to wait for the indexer
    public var indexerTimeout: TimeInterval

    /// Reply context if this is a reply message
    public var replyContext: ReplyContext?

    /// Default options (fire-and-forget, no reply)
    public static let `default` = SendOptions(
        waitForConfirmation: false,
        timeout: 10,
        waitForIndexer: false,
        indexerTimeout: 30.0,
        replyContext: nil
    )

    /// Options that wait for algod confirmation only
    public static let confirmed = SendOptions(
        waitForConfirmation: true,
        timeout: 10,
        waitForIndexer: false,
        indexerTimeout: 30.0,
        replyContext: nil
    )

    /// Options that wait for both algod confirmation and indexer visibility
    /// Use this when you need to ensure the message is immediately visible
    /// when fetching conversations (e.g., self-messages)
    public static let indexed = SendOptions(
        waitForConfirmation: true,
        timeout: 10,
        waitForIndexer: true,
        indexerTimeout: 30.0,
        replyContext: nil
    )

    public init(
        waitForConfirmation: Bool = false,
        timeout: UInt64 = 10,
        waitForIndexer: Bool = false,
        indexerTimeout: TimeInterval = 30.0,
        replyContext: ReplyContext? = nil
    ) {
        self.waitForConfirmation = waitForConfirmation
        self.timeout = timeout
        self.waitForIndexer = waitForIndexer
        self.indexerTimeout = indexerTimeout
        self.replyContext = replyContext
    }

    /// Creates options for replying to a message
    ///
    /// - Parameters:
    ///   - message: The message to reply to
    ///   - confirmed: Whether to wait for confirmation (default: false)
    ///   - indexed: Whether to wait for indexer visibility (default: false)
    ///   - timeout: Maximum rounds to wait (default: 10)
    /// - Returns: SendOptions configured for a reply
    public static func replying(
        to message: Message,
        confirmed: Bool = false,
        indexed: Bool = false,
        timeout: UInt64 = 10
    ) -> SendOptions {
        SendOptions(
            waitForConfirmation: confirmed || indexed,
            timeout: timeout,
            waitForIndexer: indexed,
            indexerTimeout: 30.0,
            replyContext: ReplyContext(replyingTo: message)
        )
    }
}
