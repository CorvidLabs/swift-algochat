import Algorand
import Foundation
import Testing
@testable import AlgoChat

@Suite("FileSendQueueStorage Tests")
struct FileSendQueueStorageTests {
    // MARK: - Test Helpers

    /// Creates a temporary file URL for testing
    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "test-queue-\(UUID().uuidString).json"
        return tempDir.appendingPathComponent(filename)
    }

    /// Creates a test address
    private func createTestAddress() throws -> Address {
        try Account().address
    }

    /// Cleans up a temp file
    private func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Save and Load Tests

    @Test("Save and load empty queue")
    func testSaveAndLoadEmpty() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)

        // Save empty
        try await storage.save([])

        // Load should return empty
        let loaded = try await storage.load()
        #expect(loaded.isEmpty)

        // File should not exist for empty queue
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Save and load single message")
    func testSaveAndLoadSingleMessage() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let address = try createTestAddress()

        let message = PendingMessage(
            recipient: address,
            content: "Hello, world!"
        )

        // Save
        try await storage.save([message])

        // File should exist
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Load
        let loaded = try await storage.load()

        #expect(loaded.count == 1)
        #expect(loaded[0].id == message.id)
        #expect(loaded[0].content == "Hello, world!")
        #expect(loaded[0].recipient == address)
        #expect(loaded[0].status == .pending)
    }

    @Test("Save and load multiple messages")
    func testSaveAndLoadMultipleMessages() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let address1 = try createTestAddress()
        let address2 = try createTestAddress()

        let messages = [
            PendingMessage(recipient: address1, content: "Message 1"),
            PendingMessage(recipient: address2, content: "Message 2"),
            PendingMessage(recipient: address1, content: "Message 3")
        ]

        // Save
        try await storage.save(messages)

        // Load
        let loaded = try await storage.load()

        #expect(loaded.count == 3)
        #expect(loaded.map(\.content) == ["Message 1", "Message 2", "Message 3"])
    }

    @Test("Load from non-existent file returns empty")
    func testLoadNonExistentFile() async throws {
        let url = createTempFileURL()
        // Don't create the file

        let storage = FileSendQueueStorage(customURL: url)
        let loaded = try await storage.load()

        #expect(loaded.isEmpty)
    }

    @Test("Save overwrites previous data")
    func testSaveOverwrites() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let address = try createTestAddress()

        // Save first set
        let messages1 = [
            PendingMessage(recipient: address, content: "First"),
            PendingMessage(recipient: address, content: "Second")
        ]
        try await storage.save(messages1)

        // Save second set (overwrites)
        let messages2 = [
            PendingMessage(recipient: address, content: "Only one now")
        ]
        try await storage.save(messages2)

        // Load should return second set
        let loaded = try await storage.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].content == "Only one now")
    }

    @Test("Clearing queue removes file")
    func testClearingRemovesFile() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let address = try createTestAddress()

        // Save a message
        try await storage.save([PendingMessage(recipient: address, content: "Test")])
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Clear (save empty)
        try await storage.save([])

        // File should be removed
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Message State Preservation Tests

    @Test("Preserves message status")
    func testPreservesMessageStatus() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let address = try createTestAddress()

        var message = PendingMessage(recipient: address, content: "Test")
        message = message.markFailed(error: "Network error")

        try await storage.save([message])
        let loaded = try await storage.load()

        #expect(loaded[0].status == .failed)
        #expect(loaded[0].retryCount == 1)
        #expect(loaded[0].lastError == "Network error")
    }

    @Test("Preserves reply context")
    func testPreservesReplyContext() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let address = try createTestAddress()

        let replyContext = ReplyContext(messageId: "TX123ABC", preview: "Original message")
        let message = PendingMessage(
            recipient: address,
            content: "Reply",
            replyContext: replyContext
        )

        try await storage.save([message])
        let loaded = try await storage.load()

        #expect(loaded[0].replyContext?.messageId == "TX123ABC")
        #expect(loaded[0].replyContext?.preview == "Original message")
    }

    @Test("Preserves timestamps")
    func testPreservesTimestamps() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let address = try createTestAddress()

        let createdAt = Date()
        var message = PendingMessage(
            recipient: address,
            content: "Test",
            createdAt: createdAt
        )
        message = message.markSending()

        try await storage.save([message])
        let loaded = try await storage.load()

        // Timestamps should be within 1 second (ISO8601 precision)
        #expect(abs(loaded[0].createdAt.timeIntervalSince(createdAt)) < 1)
        #expect(loaded[0].lastAttempt != nil)
    }

    // MARK: - Integration with SendQueue Tests

    @Test("SendQueue uses FileSendQueueStorage")
    func testSendQueueIntegration() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let queue = SendQueue(storage: storage)
        let address = try createTestAddress()

        // Enqueue messages
        try await queue.enqueue(content: "Message 1", to: address)
        try await queue.enqueue(content: "Message 2", to: address)

        // Create new queue with same storage (simulates app restart)
        let queue2 = SendQueue(storage: storage)
        try await queue2.load()

        // Should have the messages
        let pending = await queue2.getPending()
        #expect(pending.count == 2)
        #expect(pending.map(\.content).contains("Message 1"))
        #expect(pending.map(\.content).contains("Message 2"))
    }

    @Test("SendQueue persists after markSent")
    func testPersistsAfterMarkSent() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let queue = SendQueue(storage: storage)
        let address = try createTestAddress()

        // Enqueue
        let message = try await queue.enqueue(content: "Test", to: address)

        // Mark as sent
        try await queue.markSent(message.id, txid: "TX123")

        // Create new queue (simulates restart)
        let queue2 = SendQueue(storage: storage)
        try await queue2.load()

        // Should be empty (sent message removed)
        let pending = await queue2.getPending()
        #expect(pending.isEmpty)
    }

    @Test("SendQueue persists failed status")
    func testPersistsFailedStatus() async throws {
        let url = createTempFileURL()
        defer { cleanup(url: url) }

        let storage = FileSendQueueStorage(customURL: url)
        let queue = SendQueue(storage: storage)
        let address = try createTestAddress()

        // Enqueue and mark failed
        let message = try await queue.enqueue(content: "Test", to: address)
        try await queue.markFailed(message.id, error: NSError(domain: "test", code: 1))

        // Create new queue (simulates restart)
        let queue2 = SendQueue(storage: storage)
        try await queue2.load()

        // Should have the failed message
        let pending = await queue2.getPending()
        #expect(pending.count == 1)
        #expect(pending[0].status == .failed)
        #expect(pending[0].retryCount == 1)
    }
}
