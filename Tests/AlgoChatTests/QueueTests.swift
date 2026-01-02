import Algorand
import Foundation
import Testing
@testable import AlgoChat

@Suite("PendingMessage Tests")
struct PendingMessageTests {
    private let recipient = try! Account().address

    @Test("Creates pending message with defaults")
    func testCreatePendingMessage() {
        let message = PendingMessage(
            recipient: recipient,
            content: "Test message"
        )

        #expect(message.status == .pending)
        #expect(message.retryCount == 0)
        #expect(message.lastAttempt == nil)
        #expect(message.lastError == nil)
        #expect(message.replyContext == nil)
    }

    @Test("Mark as sending")
    func testMarkSending() {
        let message = PendingMessage(
            recipient: recipient,
            content: "Test message"
        )

        let sending = message.markSending()

        #expect(sending.status == .sending)
        #expect(sending.lastAttempt != nil)
        #expect(sending.retryCount == 0)
    }

    @Test("Mark as failed")
    func testMarkFailed() {
        let message = PendingMessage(
            recipient: recipient,
            content: "Test message"
        )

        let failed = message.markFailed(error: "Network error")

        #expect(failed.status == .failed)
        #expect(failed.retryCount == 1)
        #expect(failed.lastError == "Network error")
    }

    @Test("Mark as sent")
    func testMarkSent() {
        let message = PendingMessage(
            recipient: recipient,
            content: "Test message",
            status: .sending
        )

        let sent = message.markSent()

        #expect(sent.status == .sent)
    }

    @Test("Can retry check")
    func testCanRetry() {
        var message = PendingMessage(
            recipient: recipient,
            content: "Test message",
            retryCount: 2,
            status: .failed
        )

        #expect(message.canRetry(maxRetries: 3) == true)
        #expect(message.canRetry(maxRetries: 2) == false)

        message = message.markFailed(error: "Error")
        #expect(message.canRetry(maxRetries: 3) == false)
    }

    @Test("Codable round trip")
    func testCodable() throws {
        let original = PendingMessage(
            recipient: recipient,
            content: "Test message",
            replyContext: ReplyContext(messageId: "TX123", preview: "Original"),
            retryCount: 2,
            status: .failed,
            lastError: "Network error"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingMessage.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.recipient == original.recipient)
        #expect(decoded.content == original.content)
        #expect(decoded.replyContext?.messageId == original.replyContext?.messageId)
        #expect(decoded.retryCount == original.retryCount)
        #expect(decoded.status == original.status)
        #expect(decoded.lastError == original.lastError)
    }
}

@Suite("SendQueue Tests")
struct SendQueueTests {
    private let recipient = try! Account().address

    @Test("Enqueue and dequeue")
    func testEnqueueDequeue() async throws {
        let queue = SendQueue()

        let message = try await queue.enqueue(
            content: "Test message",
            to: recipient
        )

        let dequeued = await queue.dequeue()

        #expect(dequeued?.id == message.id)
        #expect(dequeued?.content == "Test message")
    }

    @Test("Dequeue returns nil when empty")
    func testDequeueEmpty() async {
        let queue = SendQueue()
        let dequeued = await queue.dequeue()
        #expect(dequeued == nil)
    }

    @Test("Mark sending")
    func testMarkSending() async throws {
        let queue = SendQueue()
        let message = try await queue.enqueue(content: "Test", to: recipient)

        try await queue.markSending(message.id)

        // Should skip sending messages
        let dequeued = await queue.dequeue()
        #expect(dequeued == nil)
    }

    @Test("Mark sent removes from queue")
    func testMarkSent() async throws {
        let queue = SendQueue()
        let message = try await queue.enqueue(content: "Test", to: recipient)

        try await queue.markSent(message.id, txid: "TX123")

        let pending = await queue.getPending()
        #expect(pending.isEmpty)
    }

    @Test("Mark failed increments retry count")
    func testMarkFailed() async throws {
        let queue = SendQueue()
        let message = try await queue.enqueue(content: "Test", to: recipient)

        try await queue.markFailed(message.id, error: NSError(domain: "test", code: 1))

        let pending = await queue.getPending()
        #expect(pending.first?.retryCount == 1)
        #expect(pending.first?.status == .failed)
    }

    @Test("Dequeue returns failed messages within retry limit")
    func testDequeueFailedRetryable() async throws {
        let queue = SendQueue(maxRetries: 3)
        let message = try await queue.enqueue(content: "Test", to: recipient)

        // Mark as failed once
        try await queue.markFailed(message.id, error: NSError(domain: "test", code: 1))

        // Should still be dequeued for retry
        let dequeued = await queue.dequeue()
        #expect(dequeued?.id == message.id)
    }

    @Test("Dequeue skips messages exceeding retry limit")
    func testDequeueSkipsMaxRetries() async throws {
        let queue = SendQueue(maxRetries: 2)
        let message = try await queue.enqueue(content: "Test", to: recipient)

        // Mark as failed twice
        try await queue.markFailed(message.id, error: NSError(domain: "test", code: 1))
        try await queue.markFailed(message.id, error: NSError(domain: "test", code: 1))

        // Should not be dequeued (max retries exceeded)
        let dequeued = await queue.dequeue()
        #expect(dequeued == nil)
    }

    @Test("Get pending for specific recipient")
    func testGetPendingForRecipient() async throws {
        let queue = SendQueue()
        let recipient2 = try Account().address

        try await queue.enqueue(content: "Message 1", to: recipient)
        try await queue.enqueue(content: "Message 2", to: recipient2)
        try await queue.enqueue(content: "Message 3", to: recipient)

        let pending = await queue.getPending(for: recipient)

        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.recipient == recipient })
    }

    @Test("Clear removes all messages")
    func testClear() async throws {
        let queue = SendQueue()

        try await queue.enqueue(content: "Test 1", to: recipient)
        try await queue.enqueue(content: "Test 2", to: recipient)

        try await queue.clear()

        #expect(await queue.isEmpty)
        #expect(await queue.count == 0)
    }

    @Test("Remove specific message")
    func testRemove() async throws {
        let queue = SendQueue()

        let message1 = try await queue.enqueue(content: "Test 1", to: recipient)
        let message2 = try await queue.enqueue(content: "Test 2", to: recipient)

        try await queue.remove(message1.id)

        let pending = await queue.getPending()
        #expect(pending.count == 1)
        #expect(pending.first?.id == message2.id)
    }
}

@Suite("InMemorySendQueueStorage Tests")
struct InMemorySendQueueStorageTests {
    private let recipient = try! Account().address

    @Test("Save and load messages")
    func testSaveAndLoad() async throws {
        let storage = InMemorySendQueueStorage()

        let messages = [
            PendingMessage(recipient: recipient, content: "Test 1"),
            PendingMessage(recipient: recipient, content: "Test 2")
        ]

        try await storage.save(messages)
        let loaded = try await storage.load()

        #expect(loaded.count == 2)
        #expect(loaded.map(\.content) == ["Test 1", "Test 2"])
    }
}
