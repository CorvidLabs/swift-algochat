import Algorand
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("InMemoryMessageCache Tests")
struct InMemoryMessageCacheTests {
    private let senderAccount = try! Account()
    private let recipientAccount = try! Account()

    private func createMessage(
        id: String,
        timestamp: Date,
        confirmedRound: UInt64 = 1000
    ) -> Message {
        Message(
            id: id,
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Test message \(id)",
            timestamp: timestamp,
            confirmedRound: confirmedRound,
            direction: .sent
        )
    }

    @Test("Store and retrieve messages")
    func testStoreAndRetrieve() async throws {
        let cache = InMemoryMessageCache()
        let participant = senderAccount.address

        let messages = [
            createMessage(id: "TX001", timestamp: Date()),
            createMessage(id: "TX002", timestamp: Date().addingTimeInterval(10))
        ]

        try await cache.store(messages, for: participant)
        let retrieved = try await cache.retrieve(for: participant, afterRound: nil)

        #expect(retrieved.count == 2)
        #expect(retrieved[0].id == "TX001")
        #expect(retrieved[1].id == "TX002")
    }

    @Test("Deduplicates messages by ID")
    func testDeduplication() async throws {
        let cache = InMemoryMessageCache()
        let participant = senderAccount.address

        let message1 = createMessage(id: "TX001", timestamp: Date())
        let message2 = createMessage(id: "TX001", timestamp: Date().addingTimeInterval(100))

        try await cache.store([message1], for: participant)
        try await cache.store([message2], for: participant)

        let retrieved = try await cache.retrieve(for: participant, afterRound: nil)
        #expect(retrieved.count == 1)
    }

    @Test("Retrieve filters by round")
    func testRetrieveAfterRound() async throws {
        let cache = InMemoryMessageCache()
        let participant = senderAccount.address

        let messages = [
            createMessage(id: "TX001", timestamp: Date(), confirmedRound: 100),
            createMessage(id: "TX002", timestamp: Date().addingTimeInterval(10), confirmedRound: 200),
            createMessage(id: "TX003", timestamp: Date().addingTimeInterval(20), confirmedRound: 300)
        ]

        try await cache.store(messages, for: participant)
        let retrieved = try await cache.retrieve(for: participant, afterRound: 150)

        #expect(retrieved.count == 2)
        #expect(retrieved.map(\.id) == ["TX002", "TX003"])
    }

    @Test("Set and get last sync round")
    func testSyncRound() async throws {
        let cache = InMemoryMessageCache()
        let participant = senderAccount.address

        let initialRound = try await cache.getLastSyncRound(for: participant)
        #expect(initialRound == nil)

        try await cache.setLastSyncRound(12345, for: participant)
        let round = try await cache.getLastSyncRound(for: participant)
        #expect(round == 12345)
    }

    @Test("Get cached conversations")
    func testGetCachedConversations() async throws {
        let cache = InMemoryMessageCache()

        let message1 = createMessage(id: "TX001", timestamp: Date())
        try await cache.store([message1], for: senderAccount.address)

        let message2 = createMessage(id: "TX002", timestamp: Date())
        try await cache.store([message2], for: recipientAccount.address)

        let conversations = try await cache.getCachedConversations()
        #expect(conversations.count == 2)
    }

    @Test("Clear all cache")
    func testClearAll() async throws {
        let cache = InMemoryMessageCache()
        let participant = senderAccount.address

        try await cache.store([createMessage(id: "TX001", timestamp: Date())], for: participant)
        try await cache.setLastSyncRound(100, for: participant)

        try await cache.clear()

        let messages = try await cache.retrieve(for: participant, afterRound: nil)
        let round = try await cache.getLastSyncRound(for: participant)

        #expect(messages.isEmpty)
        #expect(round == nil)
    }

    @Test("Clear cache for specific conversation")
    func testClearForConversation() async throws {
        let cache = InMemoryMessageCache()

        try await cache.store([createMessage(id: "TX001", timestamp: Date())], for: senderAccount.address)
        try await cache.store([createMessage(id: "TX002", timestamp: Date())], for: recipientAccount.address)

        try await cache.clear(for: senderAccount.address)

        let cleared = try await cache.retrieve(for: senderAccount.address, afterRound: nil)
        let remaining = try await cache.retrieve(for: recipientAccount.address, afterRound: nil)

        #expect(cleared.isEmpty)
        #expect(remaining.count == 1)
    }
}

@Suite("PublicKeyCache Tests")
struct PublicKeyCacheTests {
    private let testAddress = try! Account().address

    @Test("Store and retrieve public key")
    func testStoreAndRetrieve() async {
        let cache = PublicKeyCache()
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey

        await cache.store(key.rawRepresentation, for: testAddress)
        let retrieved = await cache.retrieve(for: testAddress)

        #expect(retrieved == key.rawRepresentation)
    }

    @Test("Returns nil for non-existent key")
    func testReturnsNilForMissing() async {
        let cache = PublicKeyCache()
        let retrieved = await cache.retrieve(for: testAddress)
        #expect(retrieved == nil)
    }

    @Test("Invalidates cached key")
    func testInvalidate() async {
        let cache = PublicKeyCache()
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey

        await cache.store(key.rawRepresentation, for: testAddress)
        await cache.invalidate(for: testAddress)

        let retrieved = await cache.retrieve(for: testAddress)
        #expect(retrieved == nil)
    }

    @Test("Clears all keys")
    func testClearAll() async {
        let cache = PublicKeyCache()
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey

        await cache.store(key.rawRepresentation, for: testAddress)
        await cache.clear()

        let retrieved = await cache.retrieve(for: testAddress)
        #expect(retrieved == nil)
    }

    @Test("Expired keys return nil")
    func testExpiredKeys() async throws {
        // Create cache with very short TTL
        let cache = PublicKeyCache(ttl: 0.1)  // 100ms TTL
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey

        await cache.store(key.rawRepresentation, for: testAddress)

        // Wait for expiration
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        let retrieved = await cache.retrieve(for: testAddress)
        #expect(retrieved == nil)
    }

    @Test("Non-expired keys are returned")
    func testNonExpiredKeys() async throws {
        let cache = PublicKeyCache(ttl: 10)  // 10 second TTL
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey

        await cache.store(key.rawRepresentation, for: testAddress)

        // Small wait (well under TTL)
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        let retrieved = await cache.retrieve(for: testAddress)
        #expect(retrieved == key.rawRepresentation)
    }
}
