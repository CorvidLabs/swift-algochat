import Algorand
import AlgoKit
import Foundation

/**
 Result of a successful send operation

 Contains both the transaction ID for blockchain tracking and an optimistic
 copy of the sent message for immediate local UI updates without waiting
 for indexer confirmation.
 */
public struct SendResult: Sendable {
    /// The Algorand transaction ID
    public let txid: String

    /**
     The sent message for optimistic local updates

     This message can be immediately appended to a conversation's message
     list to show the sent message before the indexer catches up.
     */
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

    /// Custom payment amount (default: 0.001 ALGO / 1000 microAlgos)
    public var amount: MicroAlgos?

    /// Default options (fire-and-forget, no reply)
    public static let `default` = SendOptions(
        waitForConfirmation: false,
        timeout: 10,
        waitForIndexer: false,
        indexerTimeout: 30.0,
        replyContext: nil,
        amount: nil
    )

    /// Options that wait for algod confirmation only
    public static let confirmed = SendOptions(
        waitForConfirmation: true,
        timeout: 10,
        waitForIndexer: false,
        indexerTimeout: 30.0,
        replyContext: nil,
        amount: nil
    )

    /**
     Options that wait for both algod confirmation and indexer visibility
     Use this when you need to ensure the message is immediately visible
     when fetching conversations (e.g., self-messages)
     */
    public static let indexed = SendOptions(
        waitForConfirmation: true,
        timeout: 10,
        waitForIndexer: true,
        indexerTimeout: 30.0,
        replyContext: nil,
        amount: nil
    )

    public init(
        waitForConfirmation: Bool = false,
        timeout: UInt64 = 10,
        waitForIndexer: Bool = false,
        indexerTimeout: TimeInterval = 30.0,
        replyContext: ReplyContext? = nil,
        amount: MicroAlgos? = nil
    ) {
        self.waitForConfirmation = waitForConfirmation
        self.timeout = timeout
        self.waitForIndexer = waitForIndexer
        self.indexerTimeout = indexerTimeout
        self.replyContext = replyContext
        self.amount = amount
    }

    /**
     Creates options for replying to a message

     - Parameters:
       - message: The message to reply to
       - confirmed: Whether to wait for confirmation (default: false)
       - indexed: Whether to wait for indexer visibility (default: false)
       - timeout: Maximum rounds to wait (default: 10)
       - amount: Custom payment amount (default: 0.001 ALGO)
     - Returns: SendOptions configured for a reply
     */
    public static func replying(
        to message: Message,
        confirmed: Bool = false,
        indexed: Bool = false,
        timeout: UInt64 = 10,
        amount: MicroAlgos? = nil
    ) -> SendOptions {
        SendOptions(
            waitForConfirmation: confirmed || indexed,
            timeout: timeout,
            waitForIndexer: indexed,
            indexerTimeout: 30.0,
            replyContext: ReplyContext(replyingTo: message),
            amount: amount
        )
    }

    /**
     Creates options with a custom payment amount

     - Parameters:
       - amount: Payment amount in microAlgos
       - confirmed: Whether to wait for confirmation (default: false)
       - indexed: Whether to wait for indexer visibility (default: false)
     - Returns: SendOptions configured with the specified amount
     */
    public static func withAmount(
        _ amount: MicroAlgos,
        confirmed: Bool = false,
        indexed: Bool = false
    ) -> SendOptions {
        SendOptions(
            waitForConfirmation: confirmed || indexed,
            timeout: 10,
            waitForIndexer: indexed,
            indexerTimeout: 30.0,
            replyContext: nil,
            amount: amount
        )
    }
}
