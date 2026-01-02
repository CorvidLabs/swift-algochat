import Algorand
import Foundation

/// Protocol for persisting the send queue
public protocol SendQueueStorage: Sendable {
    func save(_ messages: [PendingMessage]) async throws
    func load() async throws -> [PendingMessage]
}

/// Actor that manages a queue of pending messages
///
/// Messages can be enqueued when offline and sent when connectivity is restored.
public actor SendQueue {
    private var pending: [PendingMessage] = []
    private let storage: (any SendQueueStorage)?
    private let maxRetries: Int

    /// Callback for when a message permanently fails
    public var onPermanentFailure: (@Sendable (PendingMessage) -> Void)?

    /// Creates a new send queue
    ///
    /// - Parameters:
    ///   - storage: Optional storage for persistence (nil for in-memory only)
    ///   - maxRetries: Maximum number of retries before giving up (default: 3)
    public init(storage: (any SendQueueStorage)? = nil, maxRetries: Int = 3) {
        self.storage = storage
        self.maxRetries = maxRetries
    }

    /// Loads pending messages from storage
    public func load() async throws {
        guard let storage = storage else { return }
        pending = try await storage.load()
    }

    /// Adds a message to the queue
    ///
    /// - Parameter message: The pending message to enqueue
    public func enqueue(_ message: PendingMessage) async throws {
        pending.append(message)
        try await persist()
    }

    /// Creates and enqueues a new pending message
    ///
    /// - Parameters:
    ///   - content: The message content
    ///   - recipient: The recipient address
    ///   - replyContext: Optional reply context
    /// - Returns: The created pending message
    @discardableResult
    public func enqueue(
        content: String,
        to recipient: Address,
        replyContext: ReplyContext? = nil
    ) async throws -> PendingMessage {
        let message = PendingMessage(
            recipient: recipient,
            content: content,
            replyContext: replyContext
        )
        try await enqueue(message)
        return message
    }

    /// Gets the next pending message to send
    ///
    /// Returns messages in FIFO order, skipping those currently being sent.
    public func dequeue() async -> PendingMessage? {
        pending.first { $0.status == .pending || ($0.status == .failed && $0.canRetry(maxRetries: maxRetries)) }
    }

    /// Marks a message as currently sending
    ///
    /// - Parameter id: The message ID
    public func markSending(_ id: UUID) async throws {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index] = pending[index].markSending()
        try await persist()
    }

    /// Marks a message as successfully sent
    ///
    /// This removes the message from the queue.
    ///
    /// - Parameters:
    ///   - id: The message ID
    ///   - txid: The transaction ID (for logging/tracking)
    public func markSent(_ id: UUID, txid: String) async throws {
        pending.removeAll { $0.id == id }
        try await persist()
    }

    /// Marks a message as failed
    ///
    /// - Parameters:
    ///   - id: The message ID
    ///   - error: The error that occurred
    public func markFailed(_ id: UUID, error: Error) async throws {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index] = pending[index].markFailed(error: error.localizedDescription)

        // Notify if max retries exceeded
        if !pending[index].canRetry(maxRetries: maxRetries) {
            onPermanentFailure?(pending[index])
        }

        try await persist()
    }

    /// Gets all pending messages
    public func getPending() async -> [PendingMessage] {
        pending.filter { $0.status != .sent }
    }

    /// Gets pending messages for a specific recipient
    public func getPending(for recipient: Address) async -> [PendingMessage] {
        pending.filter { $0.recipient == recipient && $0.status != .sent }
    }

    /// Removes a message from the queue
    ///
    /// - Parameter id: The message ID to remove
    public func remove(_ id: UUID) async throws {
        pending.removeAll { $0.id == id }
        try await persist()
    }

    /// Removes all messages from the queue
    public func clear() async throws {
        pending.removeAll()
        try await persist()
    }

    /// Number of messages currently in the queue
    public var count: Int {
        pending.count
    }

    /// Whether the queue is empty
    public var isEmpty: Bool {
        pending.isEmpty
    }

    // MARK: - Private

    private func persist() async throws {
        guard let storage = storage else { return }
        try await storage.save(pending)
    }
}

// MARK: - In-Memory Storage

/// In-memory storage implementation (no persistence)
public actor InMemorySendQueueStorage: SendQueueStorage {
    private var messages: [PendingMessage] = []

    public init() {}

    public func save(_ messages: [PendingMessage]) async throws {
        self.messages = messages
    }

    public func load() async throws -> [PendingMessage] {
        messages
    }
}
