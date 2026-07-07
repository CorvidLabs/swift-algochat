import Algorand
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

/// Mock transaction searcher that returns pre-configured pages of results
actor MockTransactionSearcher: TransactionSearching {
    struct Page {
        let transactions: [IndexerTransaction]
        let nextToken: String?
    }

    private let pages: [String?: Page]
    private(set) var searchCallCount = 0
    private(set) var lastPageSize: Int?

    /// Creates a mock with ordered pages.
    /// First page is keyed by nil (initial request), subsequent by nextToken.
    init(pages: [Page]) {
        var dict: [String?: Page] = [:]
        for (index, page) in pages.enumerated() {
            let key: String? = index == 0 ? nil : "token-\(index)"
            // Patch the previous page's nextToken to point to this key
            if index > 0 {
                let prev = pages[index - 1]
                dict[index == 1 ? nil : "token-\(index - 1)"] = Page(
                    transactions: prev.transactions,
                    nextToken: key
                )
            }
            if index == pages.count - 1 {
                dict[key] = Page(transactions: page.transactions, nextToken: nil)
            }
        }
        // Handle single page case
        if pages.count == 1 {
            dict[nil] = Page(transactions: pages[0].transactions, nextToken: nil)
        }
        self.pages = dict
    }

    /// Creates a mock from explicit page dictionary
    init(pageDict: [String?: Page]) {
        self.pages = pageDict
    }

    func searchTransactions(
        address: Address?,
        limit: Int,
        next: String?,
        minRound: UInt64?,
        maxRound: UInt64?
    ) async throws -> TransactionsResponse {
        searchCallCount += 1
        lastPageSize = limit

        guard let page = pages[next] else {
            return try decodeResponse("""
            {"transactions": [], "current-round": 1000}
            """)
        }

        // Build JSON from page transactions
        var txJsonArray: [String] = []
        for tx in page.transactions {
            txJsonArray.append(tx.toJSON())
        }

        let nextTokenField = page.nextToken.map { ", \"next-token\": \"\($0)\"" } ?? ""
        let json = """
        {"transactions": [\(txJsonArray.joined(separator: ","))], "current-round": 1000\(nextTokenField)}
        """
        return try decodeResponse(json)
    }

    private func decodeResponse(_ json: String) throws -> TransactionsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TransactionsResponse.self, from: Data(json.utf8))
    }
}

/// Helper to build IndexerTransaction-compatible JSON
extension IndexerTransaction {
    fileprivate func toJSON() -> String {
        let noteB64 = noteData.map { $0.base64EncodedString() }
        let noteField = noteB64.map { ", \"note\": \"\($0)\"" } ?? ""
        let roundField = confirmedRound.map { ", \"confirmed-round\": \($0)" } ?? ""
        let roundTimeField = roundTime.map { ", \"round-time\": \($0)" } ?? ""
        let receiverField = paymentTransaction.map { ", \"payment-transaction\": {\"receiver\": \"\($0.receiver)\", \"amount\": \($0.amount)}" } ?? ""

        return """
        {"id": "\(id)", "sender": "\(sender)", "fee": \(fee), "tx-type": "\(txType)"\(noteField)\(roundField)\(roundTimeField)\(receiverField)}
        """
    }
}

// MARK: - Test helpers

/// Creates a valid chat envelope note data for a given sender key
private func makeEnvelopeNoteData(senderPrivateKey: Curve25519.KeyAgreement.PrivateKey, recipientPublicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
    let envelope = try MessageEncryptor.encrypt(
        message: "test",
        senderPrivateKey: senderPrivateKey,
        recipientPublicKey: recipientPublicKey
    )
    return envelope.encode()
}

/// Decodes an IndexerTransaction from JSON
private func makeTx(json: String) throws -> IndexerTransaction {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(IndexerTransaction.self, from: Data(json.utf8))
}

/// Creates a transaction with a valid chat envelope note
private func makeChatTx(
    id: String,
    sender: Address,
    receiver: Address,
    senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
    recipientPublicKey: Curve25519.KeyAgreement.PublicKey,
    round: UInt64 = 1000
) throws -> IndexerTransaction {
    let noteData = try makeEnvelopeNoteData(senderPrivateKey: senderPrivateKey, recipientPublicKey: recipientPublicKey)
    let noteB64 = noteData.base64EncodedString()
    let json = """
    {"id": "\(id)", "sender": "\(sender.description)", "fee": 1000, "tx-type": "pay", "note": "\(noteB64)", "confirmed-round": \(round), "round-time": 1700000000, "payment-transaction": {"receiver": "\(receiver.description)", "amount": 0}}
    """
    return try makeTx(json: json)
}

/// Creates a non-chat transaction (no note or non-chat note)
private func makeNonChatTx(id: String, sender: Address, receiver: Address) throws -> IndexerTransaction {
    let json = """
    {"id": "\(id)", "sender": "\(sender.description)", "fee": 1000, "tx-type": "pay", "confirmed-round": 1000, "payment-transaction": {"receiver": "\(receiver.description)", "amount": 0}}
    """
    return try makeTx(json: json)
}

// MARK: - Tests

@Suite("Paginated Key Discovery Tests")
struct PaginatedKeyDiscoveryTests {
    private let senderKey = Curve25519.KeyAgreement.PrivateKey()
    private let recipientKey = Curve25519.KeyAgreement.PrivateKey()
    private let senderAccount = try! Account()
    private let recipientAccount = try! Account()

    @Test("Finds key on first page")
    func testFindsKeyOnFirstPage() async throws {
        let chatTx = try makeChatTx(
            id: "TX1",
            sender: senderAccount.address,
            receiver: recipientAccount.address,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let mock = MockTransactionSearcher(pages: [
            .init(transactions: [chatTx], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        let discovered = try await indexer.findPublicKey(for: senderAccount.address)
        #expect(discovered.publicKey.rawRepresentation == senderKey.publicKey.rawRepresentation)
        #expect(discovered.isVerified == false)

        let callCount = await mock.searchCallCount
        #expect(callCount == 1)
    }

    @Test("Finds key on second page")
    func testFindsKeyOnSecondPage() async throws {
        let nonChatTx = try makeNonChatTx(
            id: "TX0",
            sender: senderAccount.address,
            receiver: recipientAccount.address
        )

        let chatTx = try makeChatTx(
            id: "TX1",
            sender: senderAccount.address,
            receiver: recipientAccount.address,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [nonChatTx], nextToken: "page2"),
            "page2": .init(transactions: [chatTx], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        let discovered = try await indexer.findPublicKey(for: senderAccount.address)
        #expect(discovered.publicKey.rawRepresentation == senderKey.publicKey.rawRepresentation)

        let callCount = await mock.searchCallCount
        #expect(callCount == 2)
    }

    @Test("maxPages limits search")
    func testMaxPagesLimitsSearch() async throws {
        let nonChatTx = try makeNonChatTx(
            id: "TX0",
            sender: senderAccount.address,
            receiver: recipientAccount.address
        )

        let chatTx = try makeChatTx(
            id: "TX1",
            sender: senderAccount.address,
            receiver: recipientAccount.address,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [nonChatTx], nextToken: "page2"),
            "page2": .init(transactions: [chatTx], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        // Only search 1 page — should NOT find the key
        await #expect(throws: ChatError.self) {
            _ = try await indexer.findPublicKey(for: senderAccount.address, maxPages: 1)
        }

        let callCount = await mock.searchCallCount
        #expect(callCount == 1)
    }

    @Test("Exhaustive search fetches all pages")
    func testExhaustiveSearchFetchesAllPages() async throws {
        let nonChatTx1 = try makeNonChatTx(id: "TX0", sender: senderAccount.address, receiver: recipientAccount.address)
        let nonChatTx2 = try makeNonChatTx(id: "TX1", sender: senderAccount.address, receiver: recipientAccount.address)
        let nonChatTx3 = try makeNonChatTx(id: "TX2", sender: senderAccount.address, receiver: recipientAccount.address)

        let chatTx = try makeChatTx(
            id: "TX3",
            sender: senderAccount.address,
            receiver: recipientAccount.address,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [nonChatTx1], nextToken: "p2"),
            "p2": .init(transactions: [nonChatTx2], nextToken: "p3"),
            "p3": .init(transactions: [nonChatTx3], nextToken: "p4"),
            "p4": .init(transactions: [chatTx], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        let discovered = try await indexer.findPublicKey(for: senderAccount.address)
        #expect(discovered.publicKey.rawRepresentation == senderKey.publicKey.rawRepresentation)

        let callCount = await mock.searchCallCount
        #expect(callCount == 4)
    }

    @Test("Throws publicKeyNotFound when no pages have key")
    func testThrowsWhenKeyNotFound() async throws {
        let nonChatTx = try makeNonChatTx(id: "TX0", sender: senderAccount.address, receiver: recipientAccount.address)

        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [nonChatTx], nextToken: "p2"),
            "p2": .init(transactions: [], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        await #expect(throws: ChatError.self) {
            _ = try await indexer.findPublicKey(for: senderAccount.address)
        }

        let callCount = await mock.searchCallCount
        #expect(callCount == 2)
    }

    @Test("Empty transaction history throws publicKeyNotFound")
    func testEmptyHistoryThrows() async throws {
        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        await #expect(throws: ChatError.self) {
            _ = try await indexer.findPublicKey(for: senderAccount.address)
        }
    }

    @Test("pageSize is forwarded to indexer")
    func testPageSizeForwarded() async throws {
        let chatTx = try makeChatTx(
            id: "TX1",
            sender: senderAccount.address,
            receiver: recipientAccount.address,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [chatTx], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        _ = try await indexer.findPublicKey(for: senderAccount.address, pageSize: 25)

        let pageSize = await mock.lastPageSize
        #expect(pageSize == 25)
    }

    @Test("searchDepth backward compat uses single page")
    func testSearchDepthBackwardCompat() async throws {
        let nonChatTx = try makeNonChatTx(id: "TX0", sender: senderAccount.address, receiver: recipientAccount.address)

        let chatTx = try makeChatTx(
            id: "TX1",
            sender: senderAccount.address,
            receiver: recipientAccount.address,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Key is on page 2 but searchDepth only searches 1 page
        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [nonChatTx], nextToken: "p2"),
            "p2": .init(transactions: [chatTx], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        // searchDepth overload should only search one page
        await #expect(throws: ChatError.self) {
            _ = try await indexer.findPublicKey(for: senderAccount.address, searchDepth: 100)
        }

        let callCount = await mock.searchCallCount
        #expect(callCount == 1)

        let pageSize = await mock.lastPageSize
        #expect(pageSize == 100)
    }

    @Test("Default page size constant is 50")
    func testDefaultPageSize() {
        #expect(MessageIndexer.defaultDiscoveryPageSize == 50)
    }

    @Test("Skips transactions from other senders")
    func testSkipsOtherSenders() async throws {
        let otherAccount = try Account()
        let otherKey = Curve25519.KeyAgreement.PrivateKey()

        // Transaction from a different sender — should be skipped
        let otherTx = try makeChatTx(
            id: "TX0",
            sender: otherAccount.address,
            receiver: senderAccount.address,
            senderPrivateKey: otherKey,
            recipientPublicKey: senderKey.publicKey
        )

        // Transaction from the target sender — should be found
        let chatTx = try makeChatTx(
            id: "TX1",
            sender: senderAccount.address,
            receiver: recipientAccount.address,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let mock = MockTransactionSearcher(pageDict: [
            nil: .init(transactions: [otherTx, chatTx], nextToken: nil)
        ])

        let chatAccount = try ChatAccount(account: recipientAccount)
        let indexer = MessageIndexer(transactionSearcher: mock, chatAccount: chatAccount)

        let discovered = try await indexer.findPublicKey(for: senderAccount.address)
        #expect(discovered.publicKey.rawRepresentation == senderKey.publicKey.rawRepresentation)
    }
}
