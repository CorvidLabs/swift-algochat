import Algorand
import Foundation
import Testing
@testable import AlgoChat

/// Thread-safe counter for callback testing
fileprivate final class CallbackCounter: @unchecked Sendable {
    private var _count = 0
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}

/// Thread-safe array for callback testing
fileprivate final class CallbackRecorder<T>: @unchecked Sendable {
    private var _values: [T] = []
    private let lock = NSLock()

    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }

    func append(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(value)
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _values.isEmpty
    }
}

@Suite("SyncManager Tests")
struct SyncManagerTests {
    // MARK: - Test Helpers

    private func createTestAddress() throws -> Address {
        try Account().address
    }

    // MARK: - Initialization Tests

    @Test("Creates with default online state")
    func testDefaultOnlineState() async {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        let isOnline = await manager.online
        #expect(isOnline == true)
    }

    @Test("Creates with not syncing state")
    func testDefaultNotSyncing() async {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        let isSyncing = await manager.syncing
        #expect(isSyncing == false)
    }

    // MARK: - Connectivity Tests

    @Test("setOnline updates online state")
    func testSetOnlineUpdatesState() async {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        await manager.setOnline(false)
        #expect(await manager.online == false)

        await manager.setOnline(true)
        #expect(await manager.online == true)
    }

    @Test("setOnline invokes connectivity callback")
    func testConnectivityCallback() async {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        let callbackValues = CallbackRecorder<Bool>()
        await manager.setCallback { online in
            callbackValues.append(online)
        }

        await manager.setOnline(false)
        await manager.setOnline(true)

        #expect(callbackValues.values == [false, true])
    }

    @Test("Coming online from offline triggers syncIfNeeded")
    func testComingOnlineTriggersSyncIfNeeded() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient = try createTestAddress()

        // Queue a message while "online" (default)
        try await manager.queueMessage(content: "Test", to: recipient)

        // Go offline
        await manager.setOnline(false)

        // Queue another message while offline
        try await manager.queueMessage(content: "Test 2", to: recipient)

        // Verify messages are pending
        let pendingBefore = await manager.pendingMessages()
        #expect(pendingBefore.count == 2)

        // Coming back online should trigger sync (but without a chat client, nothing happens)
        await manager.setOnline(true)

        // Messages still pending since we have no chat client
        let pendingAfter = await manager.pendingMessages()
        #expect(pendingAfter.count == 2)
    }

    // MARK: - Queue Message Tests

    @Test("queueMessage adds message to queue")
    func testQueueMessageAddsToQueue() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient = try createTestAddress()

        let message = try await manager.queueMessage(content: "Hello", to: recipient)

        #expect(message.content == "Hello")
        #expect(message.recipient == recipient)
        #expect(message.status == .pending)
    }

    @Test("queueMessage with reply context")
    func testQueueMessageWithReplyContext() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient = try createTestAddress()

        let replyContext = ReplyContext(messageId: "TX123", preview: "Original message")
        let message = try await manager.queueMessage(
            content: "Reply",
            to: recipient,
            replyContext: replyContext
        )

        #expect(message.replyContext?.messageId == "TX123")
        #expect(message.replyContext?.preview == "Original message")
    }

    // MARK: - Pending Messages Tests

    @Test("pendingMessages returns all pending")
    func testPendingMessagesReturnsAll() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient1 = try createTestAddress()
        let recipient2 = try createTestAddress()

        try await manager.queueMessage(content: "Message 1", to: recipient1)
        try await manager.queueMessage(content: "Message 2", to: recipient2)
        try await manager.queueMessage(content: "Message 3", to: recipient1)

        let pending = await manager.pendingMessages()

        #expect(pending.count == 3)
    }

    @Test("pendingMessages for specific recipient")
    func testPendingMessagesForRecipient() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient1 = try createTestAddress()
        let recipient2 = try createTestAddress()

        try await manager.queueMessage(content: "Message 1", to: recipient1)
        try await manager.queueMessage(content: "Message 2", to: recipient2)
        try await manager.queueMessage(content: "Message 3", to: recipient1)

        let pending = await manager.pendingMessages(for: recipient1)

        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.recipient == recipient1 })
    }

    // MARK: - Remove Tests

    @Test("remove removes message from queue")
    func testRemoveMessage() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient = try createTestAddress()

        let message1 = try await manager.queueMessage(content: "Message 1", to: recipient)
        let message2 = try await manager.queueMessage(content: "Message 2", to: recipient)

        try await manager.remove(message1.id)

        let pending = await manager.pendingMessages()

        #expect(pending.count == 1)
        #expect(pending.first?.id == message2.id)
    }

    // MARK: - Sync Tests

    @Test("sync without chat client does nothing")
    func testSyncWithoutChatDoesNothing() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient = try createTestAddress()

        try await manager.queueMessage(content: "Test", to: recipient)

        // Sync with nil chat
        await manager.sync(using: nil)

        // Message should still be pending
        let pending = await manager.pendingMessages()
        #expect(pending.count == 1)
    }

    @Test("syncIfNeeded respects offline state")
    func testSyncIfNeededRespectsOffline() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient = try createTestAddress()

        try await manager.queueMessage(content: "Test", to: recipient)

        // Go offline
        await manager.setOnline(false)

        // syncIfNeeded should not sync
        await manager.syncIfNeeded()

        // Message still pending
        let pending = await manager.pendingMessages()
        #expect(pending.count == 1)
    }

    @Test("syncing property reflects sync state")
    func testSyncingProperty() async {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        // Initially not syncing
        #expect(await manager.syncing == false)
    }

    // MARK: - Callback Tests

    @Test("onMessageSent callback is settable")
    func testOnMessageSentCallbackSettable() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        let sentMessages = CallbackRecorder<PendingMessage>()
        await manager.setOnMessageSent { message, _ in
            sentMessages.append(message)
        }

        // Callback is set, but won't fire without actual sync
        #expect(sentMessages.isEmpty)
    }

    @Test("onMessageFailed callback is settable")
    func testOnMessageFailedCallbackSettable() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        let failedCounter = CallbackCounter()
        await manager.setOnMessageFailed { _, _ in
            failedCounter.increment()
        }

        // Callback is set, but won't fire without actual sync
        #expect(failedCounter.count == 0)
    }

    // MARK: - Retry Tests

    @Test("retry triggers syncIfNeeded")
    func testRetryTriggersSyncIfNeeded() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let recipient = try createTestAddress()

        let message = try await manager.queueMessage(content: "Test", to: recipient)

        // Retry (without a chat client, just triggers syncIfNeeded which does nothing)
        try await manager.retry(message.id)

        // Message still pending
        let pending = await manager.pendingMessages()
        #expect(pending.count == 1)
    }
}

// MARK: - SyncManager Extension for Testing

extension SyncManager {
    /// Helper to set connectivity callback for testing
    func setCallback(_ callback: @escaping (Bool) -> Void) {
        onConnectivityChange = callback
    }

    /// Helper to set onMessageSent callback for testing
    func setOnMessageSent(_ callback: @escaping (PendingMessage, SendResult) -> Void) {
        onMessageSent = callback
    }

    /// Helper to set onMessageFailed callback for testing
    func setOnMessageFailed(_ callback: @escaping (PendingMessage, Error) -> Void) {
        onMessageFailed = callback
    }
}

@Suite("SyncManager with Storage Tests")
struct SyncManagerStorageTests {
    @Test("SyncManager works with InMemorySendQueueStorage")
    func testWithInMemoryStorage() async throws {
        let storage = InMemorySendQueueStorage()
        let queue = SendQueue(storage: storage)
        let manager = SyncManager(queue: queue)
        let recipient = try Account().address

        // Queue messages
        try await manager.queueMessage(content: "Test 1", to: recipient)
        try await manager.queueMessage(content: "Test 2", to: recipient)

        // Verify pending
        let pending = await manager.pendingMessages()
        #expect(pending.count == 2)

        // Storage should have the messages
        let stored = try await storage.load()
        #expect(stored.count == 2)
    }

    @Test("Queue persists through multiple operations")
    func testQueuePersistence() async throws {
        let storage = InMemorySendQueueStorage()
        let queue = SendQueue(storage: storage)
        let manager = SyncManager(queue: queue)
        let recipient = try Account().address

        // Add message
        let message = try await manager.queueMessage(content: "Test", to: recipient)

        // Remove message
        try await manager.remove(message.id)

        // Storage should be empty
        let stored = try await storage.load()
        #expect(stored.isEmpty)
    }
}

@Suite("SyncManager Edge Cases")
struct SyncManagerEdgeCaseTests {
    @Test("Multiple offline to online transitions")
    func testMultipleConnectivityTransitions() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        let transitionCounter = CallbackCounter()
        await manager.setCallback { _ in
            transitionCounter.increment()
        }

        // Multiple transitions
        await manager.setOnline(false)
        await manager.setOnline(true)
        await manager.setOnline(false)
        await manager.setOnline(true)

        #expect(transitionCounter.count == 4)
    }

    @Test("Setting same online state multiple times")
    func testSameOnlineStateMultipleTimes() async {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        let callbackCounter = CallbackCounter()
        await manager.setCallback { _ in
            callbackCounter.increment()
        }

        // Set to same state multiple times
        await manager.setOnline(true)
        await manager.setOnline(true)
        await manager.setOnline(true)

        // Callback should still fire each time (no debouncing)
        #expect(callbackCounter.count == 3)
    }

    @Test("Empty queue operations")
    func testEmptyQueueOperations() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)

        // These should not throw
        let pending = await manager.pendingMessages()
        #expect(pending.isEmpty)

        // Remove non-existent message should not throw
        try await manager.remove(UUID())

        // Retry non-existent message should not throw
        try await manager.retry(UUID())
    }

    @Test("Pending messages for non-existent recipient")
    func testPendingMessagesNonExistentRecipient() async throws {
        let queue = SendQueue()
        let manager = SyncManager(queue: queue)
        let existingRecipient = try Account().address
        let nonExistentRecipient = try Account().address

        try await manager.queueMessage(content: "Test", to: existingRecipient)

        let pending = await manager.pendingMessages(for: nonExistentRecipient)
        #expect(pending.isEmpty)
    }
}
