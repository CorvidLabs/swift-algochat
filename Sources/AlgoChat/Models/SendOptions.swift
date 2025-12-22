import Foundation

/// Options for sending a message
public struct SendOptions: Sendable {
    /// Whether to wait for transaction confirmation before returning
    public var waitForConfirmation: Bool

    /// Maximum rounds to wait for confirmation (if waitForConfirmation is true)
    public var timeout: UInt64

    /// Reply context if this is a reply message
    public var replyContext: ReplyContext?

    /// Default options (fire-and-forget, no reply)
    public static let `default` = SendOptions(
        waitForConfirmation: false,
        timeout: 10,
        replyContext: nil
    )

    /// Options that wait for confirmation
    public static let confirmed = SendOptions(
        waitForConfirmation: true,
        timeout: 10,
        replyContext: nil
    )

    public init(
        waitForConfirmation: Bool = false,
        timeout: UInt64 = 10,
        replyContext: ReplyContext? = nil
    ) {
        self.waitForConfirmation = waitForConfirmation
        self.timeout = timeout
        self.replyContext = replyContext
    }

    /// Creates options for replying to a message
    ///
    /// - Parameters:
    ///   - message: The message to reply to
    ///   - confirmed: Whether to wait for confirmation (default: false)
    ///   - timeout: Maximum rounds to wait (default: 10)
    /// - Returns: SendOptions configured for a reply
    public static func replying(
        to message: Message,
        confirmed: Bool = false,
        timeout: UInt64 = 10
    ) -> SendOptions {
        SendOptions(
            waitForConfirmation: confirmed,
            timeout: timeout,
            replyContext: ReplyContext(replyingTo: message)
        )
    }
}
