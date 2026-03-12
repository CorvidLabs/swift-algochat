import Algorand
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Paginated Key Discovery Tests")
struct PaginatedDiscoveryTests {

    // MARK: - scanForKeyAnnouncement Tests

    @Test("Returns nil for empty transaction list")
    func testEmptyTransactions() throws {
        let account = try ChatAccount()
        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: [],
            address: account.address
        )
        #expect(result.verified == nil)
        #expect(result.unverified == nil)
    }

    @Test("Finds verified key from signed self-transfer")
    func testFindsVerifiedKey() throws {
        let account = try ChatAccount()

        // Create signed key-publish note
        let envelope = try MessageEncryptor.encryptRaw(
            Data("{\"type\":\"key-publish\"}".utf8),
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )
        let signature = try SignatureVerifier.sign(
            encryptionPublicKey: account.encryptionPublicKey.rawRepresentation,
            with: account.account
        )
        var noteData = envelope.encode()
        noteData.append(signature)

        let tx = makeTransaction(
            id: "tx-key",
            sender: account.address.description,
            receiver: account.address.description,
            noteData: noteData
        )

        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: [tx],
            address: account.address
        )

        #expect(result.verified != nil)
        #expect(result.verified!.isVerified == true)
        #expect(result.verified!.publicKey.rawRepresentation == account.encryptionPublicKey.rawRepresentation)
    }

    @Test("Returns unverified key from unsigned envelope")
    func testFindsUnverifiedKey() throws {
        let account = try ChatAccount()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "hello",
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: recipientKey.publicKey
        )
        let noteData = envelope.encode()

        let tx = makeTransaction(
            id: "tx-msg",
            sender: account.address.description,
            receiver: recipientKey.publicKey.rawRepresentation.base64EncodedString(),
            noteData: noteData
        )

        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: [tx],
            address: account.address
        )

        #expect(result.verified == nil)
        #expect(result.unverified != nil)
        #expect(result.unverified!.isVerified == false)
        #expect(result.unverified!.publicKey.rawRepresentation == account.encryptionPublicKey.rawRepresentation)
    }

    @Test("Skips transactions from other senders")
    func testSkipsOtherSenders() throws {
        let account = try ChatAccount()
        let other = try ChatAccount()

        // Create a valid chat message from 'other', not 'account'
        let envelope = try MessageEncryptor.encrypt(
            message: "hello",
            senderPrivateKey: other.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )
        let noteData = envelope.encode()

        let tx = makeTransaction(
            id: "tx-other",
            sender: other.address.description,
            receiver: account.address.description,
            noteData: noteData
        )

        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: [tx],
            address: account.address
        )

        #expect(result.verified == nil)
        #expect(result.unverified == nil)
    }

    @Test("Skips transactions without note data")
    func testSkipsNoNoteData() throws {
        let account = try ChatAccount()

        let tx = makeTransaction(
            id: "tx-no-note",
            sender: account.address.description,
            receiver: account.address.description,
            noteData: nil
        )

        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: [tx],
            address: account.address
        )

        #expect(result.verified == nil)
        #expect(result.unverified == nil)
    }

    @Test("Skips non-chat note data")
    func testSkipsNonChatNote() throws {
        let account = try ChatAccount()

        let tx = makeTransaction(
            id: "tx-random",
            sender: account.address.description,
            receiver: account.address.description,
            noteData: Data("not a chat message".utf8)
        )

        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: [tx],
            address: account.address
        )

        #expect(result.verified == nil)
        #expect(result.unverified == nil)
    }

    @Test("Verified key takes priority over earlier unverified key in same batch")
    func testVerifiedPriorityInBatch() throws {
        let account = try ChatAccount()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // First: unverified message
        let msgEnvelope = try MessageEncryptor.encrypt(
            message: "hello",
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: recipientKey.publicKey
        )
        let txUnverified = makeTransaction(
            id: "tx-msg",
            sender: account.address.description,
            receiver: recipientKey.publicKey.rawRepresentation.base64EncodedString(),
            noteData: msgEnvelope.encode()
        )

        // Second: verified key-publish
        let keyEnvelope = try MessageEncryptor.encryptRaw(
            Data("{\"type\":\"key-publish\"}".utf8),
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )
        let signature = try SignatureVerifier.sign(
            encryptionPublicKey: account.encryptionPublicKey.rawRepresentation,
            with: account.account
        )
        var keyNoteData = keyEnvelope.encode()
        keyNoteData.append(signature)

        let txVerified = makeTransaction(
            id: "tx-key",
            sender: account.address.description,
            receiver: account.address.description,
            noteData: keyNoteData
        )

        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: [txUnverified, txVerified],
            address: account.address
        )

        #expect(result.verified != nil)
        #expect(result.verified!.isVerified == true)
    }

    @Test("Batch with only noise returns nil for both")
    func testNoiseOnlyBatch() throws {
        let account = try ChatAccount()
        let other = try ChatAccount()

        // Transaction from other address
        let envelope = try MessageEncryptor.encrypt(
            message: "noise",
            senderPrivateKey: other.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )

        let transactions = [
            makeTransaction(id: "tx1", sender: other.address.description, receiver: account.address.description, noteData: envelope.encode()),
            makeTransaction(id: "tx2", sender: account.address.description, receiver: other.address.description, noteData: nil),
            makeTransaction(id: "tx3", sender: other.address.description, receiver: account.address.description, noteData: Data("garbage".utf8)),
        ]

        let result = MessageIndexer.scanForKeyAnnouncement(
            transactions: transactions,
            address: account.address
        )

        #expect(result.verified == nil)
        #expect(result.unverified == nil)
    }

    // MARK: - Helpers

    /// Creates a mock IndexerTransaction for testing.
    private func makeTransaction(
        id: String,
        sender: String,
        receiver: String,
        noteData: Data?,
        confirmedRound: UInt64 = 100,
        roundTime: UInt64 = 1700000000
    ) -> IndexerTransaction {
        // Encode note as base64 for the JSON decoder
        let noteBase64 = noteData?.base64EncodedString()

        // Build JSON representation that IndexerTransaction can decode
        var json: [String: Any] = [
            "id": id,
            "sender": sender,
            "fee": 1000,
            "tx-type": "pay",
            "confirmed-round": confirmedRound,
            "round-time": roundTime,
            "payment-transaction": [
                "receiver": receiver,
                "amount": 0
            ] as [String: Any]
        ]

        if let noteBase64 {
            json["note"] = noteBase64
        }

        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        return try! decoder.decode(IndexerTransaction.self, from: jsonData)
    }
}
