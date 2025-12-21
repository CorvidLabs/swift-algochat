import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("ChatEnvelope Tests")
struct ChatEnvelopeTests {
    @Test("Envelope encodes and decodes correctly")
    func testEnvelopeEncodeDecode() throws {
        let senderKey = Data(repeating: 0x01, count: 32)
        let nonce = Data(repeating: 0x02, count: 12)
        let ciphertext = Data(repeating: 0x03, count: 50)

        let envelope = ChatEnvelope(
            senderPublicKey: senderKey,
            nonce: nonce,
            ciphertext: ciphertext
        )

        let encoded = envelope.encode()
        let decoded = try ChatEnvelope.decode(from: encoded)

        #expect(decoded.senderPublicKey == senderKey)
        #expect(decoded.nonce == nonce)
        #expect(decoded.ciphertext == ciphertext)
    }

    @Test("Envelope includes version and protocol bytes")
    func testEnvelopeHeader() throws {
        let envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0, count: 32),
            nonce: Data(repeating: 0, count: 12),
            ciphertext: Data(repeating: 0, count: 20)
        )

        let encoded = envelope.encode()

        #expect(encoded[0] == ChatEnvelope.version)
        #expect(encoded[1] == ChatEnvelope.protocolID)
    }

    @Test("Envelope rejects invalid version")
    func testEnvelopeRejectsInvalidVersion() throws {
        var data = Data(repeating: 0, count: 100)
        data[0] = 0xFF  // Invalid version
        data[1] = ChatEnvelope.protocolID

        #expect(throws: ChatError.self) {
            _ = try ChatEnvelope.decode(from: data)
        }
    }

    @Test("Envelope rejects data that is too short")
    func testEnvelopeRejectsTooShort() throws {
        let data = Data(repeating: 0, count: 10)

        #expect(throws: ChatError.self) {
            _ = try ChatEnvelope.decode(from: data)
        }
    }
}

@Suite("MessageEncryptor Tests")
struct MessageEncryptorTests {
    @Test("Message encryption round trip")
    func testMessageEncryptionRoundTrip() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let originalMessage = "Hello, Algorand!"

        let envelope = try MessageEncryptor.encrypt(
            message: originalMessage,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey
        )

        let decryptedMessage = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        )

        #expect(decryptedMessage == originalMessage)
    }

    @Test("Message with unicode characters")
    func testMessageWithUnicode() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let originalMessage = "Hello, World! Emoji test: 🎉🚀💎"

        let envelope = try MessageEncryptor.encrypt(
            message: originalMessage,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey
        )

        let decryptedMessage = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        )

        #expect(decryptedMessage == originalMessage)
    }

    @Test("Message too large throws error")
    func testMessageTooLargeThrows() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let largeMessage = String(repeating: "x", count: ChatEnvelope.maxPayloadSize + 100)

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.encrypt(
                message: largeMessage,
                senderPrivateKey: senderPrivateKey,
                recipientPublicKey: recipientPrivateKey.publicKey
            )
        }
    }

    @Test("Decryption with wrong key fails")
    func testDecryptionWithWrongKeyFails() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let wrongPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Secret message",
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: wrongPrivateKey
            )
        }
    }
}

@Suite("KeyDerivation Tests")
struct KeyDerivationTests {
    @Test("Public key encoding round trip")
    func testPublicKeyEncodingRoundTrip() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey

        let encoded = KeyDerivation.encodePublicKey(publicKey)
        let decoded = try KeyDerivation.decodePublicKey(from: encoded)

        #expect(decoded.rawRepresentation == publicKey.rawRepresentation)
    }

    @Test("Invalid public key size throws error")
    func testInvalidPublicKeySizeThrows() throws {
        let invalidData = Data(repeating: 0, count: 16)

        #expect(throws: ChatError.self) {
            _ = try KeyDerivation.decodePublicKey(from: invalidData)
        }
    }
}
