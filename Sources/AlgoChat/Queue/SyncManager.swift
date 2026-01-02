import Algorand
import Foundation

/// Manages synchronization of pending messages with the blockchain
///
/// The SyncManager monitors connectivity and automatically processes
/// the send queue when online.
public actor SyncManager {
    private let queue: SendQueue
    private var isSyncing = false
    private var isOnline = true

    /// Callback for when a message is successfully sent
    public var onMessageSent: ((PendingMessage, SendResult) -> Void)?

    /// Callback for when a message fails
    public var onMessageFailed: ((PendingMessage, Error) -> Void)?

    /// Callback for connectivity changes
    public var onConnectivityChange: ((Bool) -> Void)?

    /// Creates a new sync manager
    ///
    /// - Parameter queue: The send queue to manage
    public init(queue: SendQueue) {
        self.queue = queue
    }

    /// Updates connectivity status
    ///
    /// When transitioning from offline to online, automatically triggers a sync.
    ///
    /// - Parameter online: Whether the network is available
    public func setOnline(_ online: Bool) async {
        let wasOffline = !isOnline
        isOnline = online
        onConnectivityChange?(online)

        // Trigger sync when coming back online
        if wasOffline && online {
            await syncIfNeeded()
        }
    }

    /// Whether the manager thinks we're online
    public var online: Bool {
        isOnline
    }

    /// Syncs pending messages if online and not already syncing
    public func syncIfNeeded() async {
        guard isOnline, !isSyncing else { return }
        await sync(using: nil)
    }

    /// Syncs pending messages using the provided chat client
    ///
    /// - Parameter chat: The AlgoChat client to use for sending
    public func sync(using chat: AlgoChat?) async {
        guard let chat = chat, isOnline, !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        while let message = await queue.dequeue() {
            do {
                try await queue.markSending(message.id)

                // Create a conversation for sending
                let conversation = try await chat.conversation(with: message.recipient)

                // Build send options
                let options = SendOptions(
                    waitForConfirmation: true,
                    replyContext: message.replyContext
                )

                // Send the message
                let result = try await chat.send(message.content, to: conversation, options: options)

                // Mark as sent and notify
                try await queue.markSent(message.id, txid: result.txid)
                onMessageSent?(message, result)

            } catch {
                // Mark as failed
                try? await queue.markFailed(message.id, error: error)
                onMessageFailed?(message, error)

                // If it's a network error, stop trying
                if isNetworkError(error) {
                    isOnline = false
                    break
                }
            }
        }
    }

    /// Adds a message to the queue
    ///
    /// Use this when offline to queue messages for later sending.
    ///
    /// - Parameters:
    ///   - content: The message content
    ///   - recipient: The recipient address
    ///   - replyContext: Optional reply context
    /// - Returns: The pending message
    @discardableResult
    public func queueMessage(
        content: String,
        to recipient: Address,
        replyContext: ReplyContext? = nil
    ) async throws -> PendingMessage {
        try await queue.enqueue(content: content, to: recipient, replyContext: replyContext)
    }

    /// Gets all pending messages
    public func pendingMessages() async -> [PendingMessage] {
        await queue.getPending()
    }

    /// Gets pending messages for a specific recipient
    public func pendingMessages(for recipient: Address) async -> [PendingMessage] {
        await queue.getPending(for: recipient)
    }

    /// Retries a specific failed message
    public func retry(_ id: UUID) async throws {
        // The message will be picked up on next sync if it's retryable
        // We just need to trigger a sync
        await syncIfNeeded()
    }

    /// Removes a pending message
    public func remove(_ id: UUID) async throws {
        try await queue.remove(id)
    }

    /// Whether a sync is currently in progress
    public var syncing: Bool {
        isSyncing
    }

    // MARK: - Private

    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }
}
