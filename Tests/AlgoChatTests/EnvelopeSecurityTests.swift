@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Envelope Security Tests")
struct EnvelopeSecurityTests {

    // MARK: - Key Substitution Attacks

    @Test("Decryption fails when ephemeral public key is substituted")
    func testEphemeralKeySubstitution() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Secret message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        // Substitute a different ephemeral key
        let attackerKey = Curve25519.KeyAgreement.PrivateKey()
        let tampered = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: attackerKey.publicKey.rawRepresentation,
            encryptedSenderKey: envelope.encryptedSenderKey,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decrypt(
                envelope: tampered,
                recipientPrivateKey: recipient
            )
        }
    }

    @Test("Decryption fails when sender public key is substituted")
    func testSenderKeySubstitution() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Secret message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        // Substitute a different sender key — attacker tries to impersonate
        let attacker = Curve25519.KeyAgreement.PrivateKey()
        let tampered = ChatEnvelope(
            senderPublicKey: attacker.publicKey.rawRepresentation,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            encryptedSenderKey: envelope.encryptedSenderKey,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext
        )

        // Recipient should fail to decrypt (key derivation uses sender static key)
        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decrypt(
                envelope: tampered,
                recipientPrivateKey: recipient
            )
        }
    }

    // MARK: - Third-party Decryption

    @Test("Third party cannot decrypt standard envelope")
    func testThirdPartyCannotDecryptStandard() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let thirdParty = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Private conversation",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: thirdParty
            )
        }
    }

    @Test("Third party cannot decrypt PSK envelope even with correct PSK")
    func testThirdPartyCannotDecryptPSK() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let thirdParty = Curve25519.KeyAgreement.PrivateKey()

        let initialPSK = Data(repeating: 0xBB, count: 32)
        let currentPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)

        let envelope = try MessageEncryptor.encryptPSK(
            message: "PSK private message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        // Third party has the PSK but not the ECDH key — hybrid derivation should block them
        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decryptPSK(
                envelope: envelope,
                recipientPrivateKey: thirdParty,
                currentPSK: currentPSK
            )
        }
    }

    // MARK: - PSK Tampering

    @Test("PSK decryption fails with wrong PSK")
    func testWrongPSKFails() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let correctPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )
        let wrongPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xBB, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: "PSK message",
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

    @Test("PSK decryption fails with wrong ratchet counter derivation")
    func testWrongRatchetCounterFails() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let initialPSK = Data(repeating: 0xCC, count: 32)

        let correctPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 5)
        let wrongPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 6)

        let envelope = try MessageEncryptor.encryptPSK(
            message: "Counter-specific message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: correctPSK,
            ratchetCounter: 5
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decryptPSK(
                envelope: envelope,
                recipientPrivateKey: recipient,
                currentPSK: wrongPSK
            )
        }
    }

    // MARK: - Truncation Attacks

    @Test("Standard envelope truncated at header boundary throws error")
    func testStandardTruncatedAtHeader() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Will be truncated",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let encoded = envelope.encode()

        // Truncate to just the header (no ciphertext tag)
        let truncated = encoded.prefix(ChatEnvelope.headerSize)
        #expect(throws: ChatError.self) {
            _ = try ChatEnvelope.decode(from: truncated)
        }
    }

    @Test("PSK envelope truncated at header boundary throws error")
    func testPSKTruncatedAtHeader() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: "Will be truncated",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let encoded = envelope.encode()

        // Truncate to just the header
        let truncated = encoded.prefix(PSKEnvelope.headerSize)
        #expect(throws: ChatError.self) {
            _ = try PSKEnvelope.decode(from: truncated)
        }
    }

    @Test("Envelope with only version and protocol bytes throws error")
    func testMinimalHeaderOnly() throws {
        let data = Data([ChatEnvelope.version, ChatEnvelope.protocolID])
        #expect(throws: ChatError.self) {
            _ = try ChatEnvelope.decode(from: data)
        }
    }

    // MARK: - Tampered Encrypted Sender Key

    @Test("Tampered encrypted sender key blocks sender decryption")
    func testTamperedEncryptedSenderKey() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Sender should re-read this",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        // Tamper with the encrypted sender key
        var tamperedKey = envelope.encryptedSenderKey
        tamperedKey[0] ^= 0xFF

        let tampered = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            encryptedSenderKey: tamperedKey,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext
        )

        // Sender tries to decrypt their own message — should fail
        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decrypt(
                envelope: tampered,
                recipientPrivateKey: sender
            )
        }

        // Recipient should still be able to decrypt (doesn't use encrypted sender key)
        let content = try MessageEncryptor.decrypt(
            envelope: tampered,
            recipientPrivateKey: recipient
        )
        #expect(content?.text == "Sender should re-read this")
    }

    // MARK: - Encode/Decode Round-trip Integrity

    @Test("Standard envelope encode/decode round-trip preserves all fields")
    func testStandardRoundTrip() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let original = try MessageEncryptor.encrypt(
            message: "Round-trip test",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let encoded = original.encode()
        let decoded = try ChatEnvelope.decode(from: encoded)

        #expect(decoded.senderPublicKey == original.senderPublicKey)
        #expect(decoded.ephemeralPublicKey == original.ephemeralPublicKey)
        #expect(decoded.encryptedSenderKey == original.encryptedSenderKey)
        #expect(decoded.nonce == original.nonce)
        #expect(decoded.ciphertext == original.ciphertext)
    }

    @Test("PSK envelope encode/decode round-trip preserves all fields")
    func testPSKRoundTrip() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xDD, count: 32), counter: 42
        )

        let original = try MessageEncryptor.encryptPSK(
            message: "PSK round-trip",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 42
        )

        let encoded = original.encode()
        let decoded = try PSKEnvelope.decode(from: encoded)

        #expect(decoded.ratchetCounter == 42)
        #expect(decoded.senderPublicKey == original.senderPublicKey)
        #expect(decoded.ephemeralPublicKey == original.ephemeralPublicKey)
        #expect(decoded.nonce == original.nonce)
        #expect(decoded.encryptedSenderKey == original.encryptedSenderKey)
        #expect(decoded.ciphertext == original.ciphertext)
    }

    // MARK: - Bidirectional Decryption Correctness

    @Test("Both sender and recipient decrypt to same plaintext")
    func testBidirectionalDecryption() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let message = "Bidirectional test message"

        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let recipientResult = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipient
        )
        let senderResult = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: sender
        )

        #expect(recipientResult?.text == message)
        #expect(senderResult?.text == message)
    }

    @Test("PSK bidirectional decryption produces same plaintext")
    func testPSKBidirectionalDecryption() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let message = "PSK bidirectional test"
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xEE, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: message,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let recipientResult = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: recipient,
            currentPSK: currentPSK
        )
        let senderResult = try MessageEncryptor.decryptPSK(
            envelope: envelope,
            recipientPrivateKey: sender,
            currentPSK: currentPSK
        )

        #expect(recipientResult?.text == message)
        #expect(senderResult?.text == message)
    }
}
