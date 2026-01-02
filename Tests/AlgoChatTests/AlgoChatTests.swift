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

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.text == originalMessage)
        #expect(decrypted.replyToId == nil)
        #expect(decrypted.replyToPreview == nil)
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

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.text == originalMessage)
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

    @Test("Reply message encryption round trip preserves metadata")
    func testReplyEncryptionRoundTrip() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let replyText = "This is my reply!"
        let originalTxid = "TX123456789ABCDEF"
        let originalPreview = "The original message that was sent"

        let envelope = try MessageEncryptor.encrypt(
            message: replyText,
            replyTo: (txid: originalTxid, preview: originalPreview),
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.text == replyText)
        #expect(decrypted.replyToId == originalTxid)
        #expect(decrypted.replyToPreview == originalPreview)
    }

    @Test("Reply formatted content includes quoted preview")
    func testReplyFormattedContent() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Yes, I agree!",
            replyTo: (txid: "TX123", preview: "Do you want to proceed?"),
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.formattedContent.contains("> Do you want to proceed?"))
        #expect(decrypted.formattedContent.contains("Yes, I agree!"))
    }

    @Test("Reply preview truncates long original messages")
    func testReplyPreviewTruncation() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let longOriginal = String(repeating: "x", count: 100)

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply!",
            replyTo: (txid: "TX123", preview: longOriginal),
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        // Preview should be truncated to 80 chars (77 + "...")
        #expect(decrypted.replyToPreview!.count == 80)
        #expect(decrypted.replyToPreview!.hasSuffix("..."))
    }

    @Test("Plain text backward compatibility")
    func testPlainTextBackwardCompatibility() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        // Plain text message (old v1 format)
        let plainMessage = "Just a plain message without JSON"

        let envelope = try MessageEncryptor.encrypt(
            message: plainMessage,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.text == plainMessage)
        #expect(decrypted.replyToId == nil)
        #expect(decrypted.formattedContent == plainMessage)
    }

    @Test("Key publish payload returns nil from decrypt")
    func testKeyPublishPayloadReturnsNil() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        // Create key-publish payload
        let payload = KeyPublishPayload()
        let payloadData = try JSONEncoder().encode(payload)

        let envelope = try MessageEncryptor.encryptRaw(
            payloadData,
            senderPrivateKey: privateKey,
            recipientPublicKey: privateKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: privateKey
        )

        #expect(decrypted == nil)
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
