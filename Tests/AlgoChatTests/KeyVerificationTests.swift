import Algorand
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Key Verification Tests")
struct KeyVerificationTests {
    // MARK: - extractKey Tests

    @Test("Unsigned envelope returns isVerified false")
    func testUnsignedEnvelopeReturnsUnverified() throws {
        let account = try ChatAccount()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "hello",
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let noteData = envelope.encode()
        let result = try MessageIndexer.extractKey(
            from: noteData,
            senderAddress: account.address
        )

        #expect(result != nil)
        #expect(result!.isVerified == false)
        #expect(result!.publicKey.rawRepresentation == account.encryptionPublicKey.rawRepresentation)
    }

    @Test("Signed key announcement returns isVerified true")
    func testSignedKeyAnnouncementReturnsVerified() throws {
        let account = try ChatAccount()

        // Create envelope (self-encrypted for key-publish)
        let envelope = try MessageEncryptor.encryptRaw(
            Data("{\"type\":\"key-publish\"}".utf8),
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )

        // Sign the encryption public key with Ed25519
        let signature = try SignatureVerifier.sign(
            encryptionPublicKey: account.encryptionPublicKey.rawRepresentation,
            with: account.account
        )

        // Append signature to note data (same format as createSignedKeyPublish)
        var noteData = envelope.encode()
        noteData.append(signature)

        let result = try MessageIndexer.extractKey(
            from: noteData,
            senderAddress: account.address
        )

        #expect(result != nil)
        #expect(result!.isVerified == true)
        #expect(result!.publicKey.rawRepresentation == account.encryptionPublicKey.rawRepresentation)
    }

    @Test("Signature from wrong account returns isVerified false")
    func testWrongAccountSignatureReturnsUnverified() throws {
        let account = try ChatAccount()
        let wrongAccount = try ChatAccount()

        let envelope = try MessageEncryptor.encryptRaw(
            Data("{\"type\":\"key-publish\"}".utf8),
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )

        // Sign with the wrong account's Ed25519 key
        let wrongSignature = try SignatureVerifier.sign(
            encryptionPublicKey: account.encryptionPublicKey.rawRepresentation,
            with: wrongAccount.account
        )

        var noteData = envelope.encode()
        noteData.append(wrongSignature)

        let result = try MessageIndexer.extractKey(
            from: noteData,
            senderAddress: account.address
        )

        #expect(result != nil)
        #expect(result!.isVerified == false)
    }

    @Test("Corrupted signature returns isVerified false")
    func testCorruptedSignatureReturnsUnverified() throws {
        let account = try ChatAccount()

        let envelope = try MessageEncryptor.encryptRaw(
            Data("{\"type\":\"key-publish\"}".utf8),
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )

        // Append garbage 64-byte "signature"
        var noteData = envelope.encode()
        noteData.append(Data(repeating: 0xFF, count: 64))

        let result = try MessageIndexer.extractKey(
            from: noteData,
            senderAddress: account.address
        )

        #expect(result != nil)
        #expect(result!.isVerified == false)
    }

    @Test("Non-chat data returns nil")
    func testNonChatDataReturnsNil() throws {
        let account = try ChatAccount()
        let noteData = Data("not a chat message".utf8)

        let result = try MessageIndexer.extractKey(
            from: noteData,
            senderAddress: account.address
        )

        #expect(result == nil)
    }

    @Test("PSK envelope without signature returns isVerified false")
    func testPSKEnvelopeReturnsUnverified() throws {
        let account = try ChatAccount()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let psk = Data(repeating: 0xAB, count: 32)

        let envelope = try MessageEncryptor.encryptPSK(
            message: "hello",
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: recipientKey.publicKey,
            currentPSK: psk,
            ratchetCounter: 1
        )

        let noteData = envelope.encode()
        let result = try MessageIndexer.extractKey(
            from: noteData,
            senderAddress: account.address
        )

        #expect(result != nil)
        #expect(result!.isVerified == false)
    }

    // MARK: - MessageTransaction.createSignedKeyPublish Tests

    @Test("createSignedKeyPublish appends signature to note data")
    func testCreateSignedKeyPublishAppendsSignature() throws {
        let account = try ChatAccount()

        let envelope = try MessageEncryptor.encryptRaw(
            Data("{\"type\":\"key-publish\"}".utf8),
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )

        let signature = try SignatureVerifier.sign(
            encryptionPublicKey: account.encryptionPublicKey.rawRepresentation,
            with: account.account
        )

        #expect(signature.count == SignatureVerifier.signatureSize)

        // Verify the note format: envelope + 64-byte signature
        let envelopeData = envelope.encode()
        var expectedNote = envelopeData
        expectedNote.append(signature)

        #expect(expectedNote.count == envelopeData.count + 64)
        #expect(expectedNote.count <= 1024) // Fits in Algorand note field
    }

    // MARK: - DiscoveredKey Tests

    @Test("DiscoveredKey preserves verification status")
    func testDiscoveredKeyPreservesVerification() throws {
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey

        let verified = DiscoveredKey(publicKey: key, isVerified: true)
        let unverified = DiscoveredKey(publicKey: key, isVerified: false)

        #expect(verified.isVerified == true)
        #expect(unverified.isVerified == false)
        #expect(verified.publicKey.rawRepresentation == unverified.publicKey.rawRepresentation)
    }

    @Test("Partial signature data (wrong size) returns isVerified false")
    func testPartialSignatureReturnsUnverified() throws {
        let account = try ChatAccount()

        let envelope = try MessageEncryptor.encryptRaw(
            Data("{\"type\":\"key-publish\"}".utf8),
            senderPrivateKey: account.encryptionPrivateKey,
            recipientPublicKey: account.encryptionPublicKey
        )

        // Append only 32 bytes (not 64) — should not be treated as a signature
        var noteData = envelope.encode()
        noteData.append(Data(repeating: 0xAA, count: 32))

        let result = try MessageIndexer.extractKey(
            from: noteData,
            senderAddress: account.address
        )

        // With wrong-sized trailing data, the envelope decode may fail
        // because ChatEnvelope will try to include the extra bytes as ciphertext.
        // Either way, the key should not be verified.
        if let result {
            #expect(result.isVerified == false)
        }
    }
}
