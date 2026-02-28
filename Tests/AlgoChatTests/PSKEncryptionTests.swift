@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("PSK Encryption Tests", .serialized)
struct PSKEncryptionTests {

    // MARK: - Round-Trip

    @Test("Encrypt and decrypt PSK message round-trip")
    func testRoundTrip() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let psk = Data(repeating: 0xAA, count: 32)
        let currentPSK = PSKRatchet.derivePSKAtCounter(initialPSK: psk, counter: 0)

        let message = "Hello, PSK mode!"
        let envelope = try MessageEncryptor.encryptPSK(
            message: message,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let decrypted = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: recipient,
            currentPSK: currentPSK
        )

        #expect(decrypted?.text == message)
    }

    @Test("Sender can decrypt own PSK messages (bidirectional)")
    func testSenderDecryption() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let psk = Data(repeating: 0xBB, count: 32)
        let currentPSK = PSKRatchet.derivePSKAtCounter(initialPSK: psk, counter: 5)

        let message = "Can sender decrypt?"
        let envelope = try MessageEncryptor.encryptPSK(
            message: message,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 5
        )

        // Sender decrypts using their own private key
        let decrypted = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: sender,
            currentPSK: currentPSK
        )

        #expect(decrypted?.text == message)
    }

    // MARK: - Security

    @Test("Wrong PSK fails decryption")
    func testWrongPSK() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let correctPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )
        let wrongPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xBB, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: "Secret",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: correctPSK,
            ratchetCounter: 0
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decryptPSK(
                envelope: envelope,
                recipientPrivateKey: recipient,
                currentPSK: wrongPSK
            )
        }
    }

    @Test("Wrong private key fails decryption")
    func testWrongPrivateKey() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let eve = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: "For Bob only",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decryptPSK(
                envelope: envelope,
                recipientPrivateKey: eve,
                currentPSK: currentPSK
            )
        }
    }

    // MARK: - Reply Metadata

    @Test("Reply metadata preserved through PSK encrypt/decrypt")
    func testReplyMetadata() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: "This is a reply",
            replyTo: (txid: "TX12345", preview: "Original message"),
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let decrypted = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: recipient,
            currentPSK: currentPSK
        )

        #expect(decrypted?.text == "This is a reply")
        #expect(decrypted?.replyToId == "TX12345")
        #expect(decrypted?.replyToPreview == "Original message")
    }

    // MARK: - Unicode

    @Test("Unicode messages work with PSK encryption")
    func testUnicodeMessage() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xCC, count: 32), counter: 0
        )

        let message = "Hello! 你好 مرحبا 🎉🌅 Héllo"
        let envelope = try MessageEncryptor.encryptPSK(
            message: message,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let decrypted = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: recipient,
            currentPSK: currentPSK
        )

        #expect(decrypted?.text == message)
    }

    // MARK: - Protocol Spec Test Vector (Test Case 4.3)

    @Test("Full encryption round-trip with protocol spec test vectors")
    func testProtocolSpecRoundTrip() throws {
        let senderSeed = Data(repeating: 0x01, count: 32)
        let recipientSeed = Data(repeating: 0x02, count: 32)

        let senderPrivate = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: senderSeed)
        let recipientPrivate = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: recipientSeed)

        let initialPSK = Data(repeating: 0xAA, count: 32)
        let currentPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)

        // Encrypt
        let message = "Hello, AlgoChat!"
        let envelope = try MessageEncryptor.encryptPSK(
            message: message,
            senderPrivateKey: senderPrivate,
            recipientPublicKey: recipientPrivate.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        // Verify envelope fields
        #expect(envelope.ratchetCounter == 0)
        #expect(envelope.senderPublicKey == senderPrivate.publicKey.rawRepresentation)

        // Decrypt as recipient
        let recipientDecrypted = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: recipientPrivate,
            currentPSK: currentPSK
        )
        #expect(recipientDecrypted?.text == message)

        // Decrypt as sender
        let senderDecrypted = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: senderPrivate,
            currentPSK: currentPSK
        )
        #expect(senderDecrypted?.text == message)
    }

    // MARK: - Multiple Counters

    @Test("Different counters produce different envelopes")
    func testDifferentCounters() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let initialPSK = Data(repeating: 0xAA, count: 32)

        let psk0 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)
        let psk1 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 1)

        let envelope0 = try MessageEncryptor.encryptPSK(
            message: "Same message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: psk0,
            ratchetCounter: 0
        )

        let envelope1 = try MessageEncryptor.encryptPSK(
            message: "Same message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: psk1,
            ratchetCounter: 1
        )

        // Counter values should differ
        #expect(envelope0.ratchetCounter == 0)
        #expect(envelope1.ratchetCounter == 1)

        // Each decrypts with its own PSK
        let d0 = try MessageEncryptor.decryptPSK(
            envelope: envelope0,
            recipientPrivateKey: recipient,
            currentPSK: psk0
        )
        let d1 = try MessageEncryptor.decryptPSK(
            envelope: envelope1,
            recipientPrivateKey: recipient,
            currentPSK: psk1
        )

        #expect(d0?.text == "Same message")
        #expect(d1?.text == "Same message")
    }

    // MARK: - Envelope Size

    @Test("PSK envelope fits within 1024-byte Algorand note limit")
    func testEnvelopeFitsInNote() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        // Max payload message
        let maxMessage = String(repeating: "A", count: 878)
        let envelope = try MessageEncryptor.encryptPSK(
            message: maxMessage,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let encoded = envelope.encode()
        #expect(encoded.count <= 1024, "Encoded envelope must fit in 1024-byte note field")
    }

    @Test("Oversized PSK message throws error")
    func testOversizedMessage() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        let tooLong = String(repeating: "A", count: 879)
        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.encryptPSK(
                message: tooLong,
                senderPrivateKey: sender,
                recipientPublicKey: recipient.publicKey,
                currentPSK: currentPSK,
                ratchetCounter: 0
            )
        }
    }
}
