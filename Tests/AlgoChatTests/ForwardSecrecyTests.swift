@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

#if canImport(Security)
import Security
#endif

@Suite("EphemeralKeyManager Tests")
struct EphemeralKeyManagerTests {
    private let keyManager = EphemeralKeyManager()

    @Test("Generates unique key pairs")
    func testGeneratesUniqueKeyPairs() {
        let key1 = keyManager.generateKeyPair()
        let key2 = keyManager.generateKeyPair()

        #expect(key1.publicKey.rawRepresentation != key2.publicKey.rawRepresentation)
    }

    @Test("Derives encryption key")
    func testDerivesEncryptionKey() throws {
        let ephemeralKey = keyManager.generateKeyPair()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let senderStaticKey = Curve25519.KeyAgreement.PrivateKey()

        let symmetricKey = try keyManager.deriveEncryptionKey(
            ephemeralPrivateKey: ephemeralKey,
            recipientPublicKey: recipientKey.publicKey,
            senderStaticPublicKey: senderStaticKey.publicKey
        )

        // Key should be 32 bytes (256 bits)
        #expect(symmetricKey.bitCount == 256)
    }

    @Test("Encryption and decryption keys match")
    func testEncryptionDecryptionKeysMatch() throws {
        let ephemeralKey = keyManager.generateKeyPair()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let senderStaticKey = Curve25519.KeyAgreement.PrivateKey()

        let encryptionKey = try keyManager.deriveEncryptionKey(
            ephemeralPrivateKey: ephemeralKey,
            recipientPublicKey: recipientKey.publicKey,
            senderStaticPublicKey: senderStaticKey.publicKey
        )

        let decryptionKey = try keyManager.deriveDecryptionKey(
            recipientPrivateKey: recipientKey,
            ephemeralPublicKey: ephemeralKey.publicKey,
            senderStaticPublicKey: senderStaticKey.publicKey
        )

        // Both keys should derive the same symmetric key
        #expect(encryptionKey == decryptionKey)
    }

    @Test("Different ephemeral keys produce different symmetric keys")
    func testDifferentEphemeralKeysDifferentSymmetricKeys() throws {
        let ephemeralKey1 = keyManager.generateKeyPair()
        let ephemeralKey2 = keyManager.generateKeyPair()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let senderStaticKey = Curve25519.KeyAgreement.PrivateKey()

        let key1 = try keyManager.deriveEncryptionKey(
            ephemeralPrivateKey: ephemeralKey1,
            recipientPublicKey: recipientKey.publicKey,
            senderStaticPublicKey: senderStaticKey.publicKey
        )

        let key2 = try keyManager.deriveEncryptionKey(
            ephemeralPrivateKey: ephemeralKey2,
            recipientPublicKey: recipientKey.publicKey,
            senderStaticPublicKey: senderStaticKey.publicKey
        )

        #expect(key1 != key2)
    }
}

@Suite("ChatEnvelope Tests")
struct ChatEnvelopeForwardSecrecyTests {
    @Test("Envelope has correct version")
    func testVersion() {
        let envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            encryptedSenderKey: Data(repeating: 0x03, count: 48),
            nonce: Data(repeating: 0x04, count: 12),
            ciphertext: Data(repeating: 0x05, count: 50)
        )

        #expect(envelope.encode()[0] == ChatEnvelope.version)
    }

    @Test("Envelope encodes correctly")
    func testEncode() {
        let senderKey = Data(repeating: 0x01, count: 32)
        let ephemeralKey = Data(repeating: 0x02, count: 32)
        let encryptedSenderKey = Data(repeating: 0x03, count: 48)
        let nonce = Data(repeating: 0x04, count: 12)
        let ciphertext = Data(repeating: 0x05, count: 50)

        let envelope = ChatEnvelope(
            senderPublicKey: senderKey,
            ephemeralPublicKey: ephemeralKey,
            encryptedSenderKey: encryptedSenderKey,
            nonce: nonce,
            ciphertext: ciphertext
        )

        let encoded = envelope.encode()

        #expect(encoded[0] == ChatEnvelope.version)
        #expect(encoded[1] == ChatEnvelope.protocolID)
        #expect(Data(encoded[2..<34]) == senderKey)
        #expect(Data(encoded[34..<66]) == ephemeralKey)
        #expect(Data(encoded[66..<78]) == nonce)
        #expect(Data(encoded[78..<126]) == encryptedSenderKey)
        #expect(Data(encoded[126...]) == ciphertext)
    }

    @Test("Envelope decode round trip")
    func testDecodeRoundTrip() throws {
        let original = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            encryptedSenderKey: Data(repeating: 0x03, count: 48),
            nonce: Data(repeating: 0x04, count: 12),
            ciphertext: Data(repeating: 0x05, count: 50)
        )

        let encoded = original.encode()
        let decoded = try ChatEnvelope.decode(from: encoded)

        #expect(decoded.senderPublicKey == original.senderPublicKey)
        #expect(decoded.ephemeralPublicKey == original.ephemeralPublicKey)
        #expect(decoded.encryptedSenderKey == original.encryptedSenderKey)
        #expect(decoded.nonce == original.nonce)
        #expect(decoded.ciphertext == original.ciphertext)
    }

    @Test("Header size is correct")
    func testHeaderSize() {
        // version(1) + protocol(1) + sender(32) + ephemeral(32) + nonce(12) + encryptedSenderKey(48) = 126
        #expect(ChatEnvelope.headerSize == 126)
    }

    @Test("Max payload size is correct")
    func testMaxPayloadSize() {
        // 1024 byte note - 126 byte header - 16 byte tag = 882
        #expect(ChatEnvelope.maxPayloadSize == 882)
    }

    @Test("Decode fails for unsupported version")
    func testDecodeUnsupportedVersion() {
        var data = Data([0x99, ChatEnvelope.protocolID])
        data.append(Data(repeating: 0x00, count: 200))

        #expect(throws: ChatError.self) {
            try ChatEnvelope.decode(from: data)
        }
    }

    @Test("Decode fails for unsupported protocol")
    func testDecodeUnsupportedProtocol() {
        var data = Data([ChatEnvelope.version, 0x99])
        data.append(Data(repeating: 0x00, count: 200))

        #expect(throws: ChatError.self) {
            try ChatEnvelope.decode(from: data)
        }
    }

    @Test("Decode fails for data too short")
    func testDecodeDataTooShort() {
        let data = Data([ChatEnvelope.version])

        #expect(throws: ChatError.self) {
            try ChatEnvelope.decode(from: data)
        }
    }
}

@Suite("Encryption Tests")
struct EncryptionTests {
    @Test("Encrypt produces envelope with forward secrecy")
    func testEncryptProducesEnvelope() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Hello, World!",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        #expect(envelope.ephemeralPublicKey.count == 32)
        #expect(envelope.encryptedSenderKey.count == 48)
    }

    @Test("Ephemeral key differs from sender key")
    func testEphemeralKeyDiffersFromSender() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Test",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        #expect(envelope.ephemeralPublicKey != envelope.senderPublicKey)
    }

    @Test("Each message has unique ephemeral key")
    func testUniqueEphemeralKeys() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope1 = try MessageEncryptor.encrypt(
            message: "Message 1",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let envelope2 = try MessageEncryptor.encrypt(
            message: "Message 2",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        #expect(envelope1.ephemeralPublicKey != envelope2.ephemeralPublicKey)
    }

    @Test("Recipient can decrypt message")
    func testRecipientDecryption() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let message = "Hello, forward secrecy!"

        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == message)
    }

    @Test("Sender can decrypt their own message")
    func testSenderDecryption() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let message = "Sender should be able to read this!"

        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Sender decrypts their own message using their own private key
        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: senderKey
        )

        #expect(decrypted?.text == message)
    }

    @Test("Both sender and recipient can decrypt")
    func testBidirectionalDecryption() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let message = "Both parties should read this!"

        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Recipient decrypts
        let recipientDecrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )
        #expect(recipientDecrypted?.text == message)

        // Sender decrypts their own message
        let senderDecrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: senderKey
        )
        #expect(senderDecrypted?.text == message)
    }

    @Test("Encrypt with reply context")
    func testEncryptWithReply() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "This is a reply",
            replyTo: (txid: "TX123ABC", preview: "Original message"),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == "This is a reply")
        #expect(decrypted?.replyToId == "TX123ABC")
        #expect(decrypted?.replyToPreview == "Original message")
    }

    @Test("EncryptRaw works correctly")
    func testEncryptRaw() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let data = Data("Raw data payload".utf8)

        let envelope = try MessageEncryptor.encryptRaw(
            data,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        #expect(envelope.ephemeralPublicKey.count == 32)
    }

    @Test("Decryption fails with wrong key")
    func testDecryptionFailsWithWrongKey() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let wrongKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Secret message",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        #expect(throws: Error.self) {
            _ = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: wrongKey
            )
        }
    }

    @Test("Message too large throws error")
    func testMessageTooLargeThrows() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Create a message larger than max payload size (882 bytes)
        let largeMessage = String(repeating: "A", count: 1000)

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.encrypt(
                message: largeMessage,
                senderPrivateKey: senderKey,
                recipientPublicKey: recipientKey.publicKey
            )
        }
    }

    @Test("Empty message encrypts successfully")
    func testEmptyMessageEncrypts() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == "")
    }

    @Test("Unicode message round trip")
    func testUnicodeMessageRoundTrip() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let message = "Hello! "

        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == message)
    }
}

@Suite("Edge Case Tests")
struct EdgeCaseTests {
    @Test("Tampered ephemeral public key fails decryption")
    func testTamperedEphemeralKey() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Secret message",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Tamper with the ephemeral public key
        var tamperedEphemeralKey = envelope.ephemeralPublicKey
        tamperedEphemeralKey[0] ^= 0xFF  // Flip bits

        let tamperedEnvelope = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: tamperedEphemeralKey,
            encryptedSenderKey: envelope.encryptedSenderKey,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext
        )

        // Decryption should fail (wrong shared secret derived)
        #expect(throws: Error.self) {
            _ = try MessageEncryptor.decrypt(
                envelope: tamperedEnvelope,
                recipientPrivateKey: recipientKey
            )
        }
    }

    @Test("Insufficient ciphertext size fails")
    func testInsufficientCiphertextSize() throws {
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Create envelope with ciphertext smaller than auth tag (16 bytes)
        let envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            encryptedSenderKey: Data(repeating: 0x03, count: 48),
            nonce: Data(repeating: 0x04, count: 12),
            ciphertext: Data(repeating: 0x05, count: 10)  // Only 10 bytes, need at least 16
        )

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: recipientKey
            )
        }
    }

    @Test("Boundary size message at exactly max")
    func testBoundarySizeMax() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Max payload is 882 bytes
        let maxMessage = String(repeating: "A", count: ChatEnvelope.maxPayloadSize)

        let envelope = try MessageEncryptor.encrypt(
            message: maxMessage,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == maxMessage)
    }

    @Test("Boundary size message one byte under max")
    func testBoundarySizeOneUnderMax() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let message = String(repeating: "B", count: ChatEnvelope.maxPayloadSize - 1)

        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == message)
    }

    @Test("Boundary size message one byte over max fails")
    func testBoundarySizeOneOverMax() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let message = String(repeating: "X", count: ChatEnvelope.maxPayloadSize + 1)

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.encrypt(
                message: message,
                senderPrivateKey: senderKey,
                recipientPublicKey: recipientKey.publicKey
            )
        }
    }

    @Test("Reply with special characters in preview")
    func testReplyWithSpecialCharacters() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Special characters: newlines, quotes, unicode, backslashes
        let specialPreview = "Line1\nLine2\t\"quoted\" \\ emoji: 🎉"

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply message",
            replyTo: (txid: "TX_SPECIAL_123", preview: specialPreview),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == "Reply message")
        #expect(decrypted?.replyToId == "TX_SPECIAL_123")
        #expect(decrypted?.replyToPreview == specialPreview)
    }

    @Test("Corrupted sender public key in envelope")
    func testCorruptedSenderPublicKey() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Test",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Create envelope with all-zero sender key (invalid point on curve)
        let corruptedEnvelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x00, count: 32),
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            encryptedSenderKey: envelope.encryptedSenderKey,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext
        )

        // Decryption will fail because HKDF info will be wrong
        #expect(throws: Error.self) {
            _ = try MessageEncryptor.decrypt(
                envelope: corruptedEnvelope,
                recipientPrivateKey: recipientKey
            )
        }
    }

    @Test("Invalid nonce in ChaCha20 decryption")
    func testInvalidNonceInDecryption() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Test message",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Flip bits in nonce
        var tamperedNonce = envelope.nonce
        tamperedNonce[0] ^= 0xFF

        let tamperedEnvelope = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            encryptedSenderKey: envelope.encryptedSenderKey,
            nonce: tamperedNonce,
            ciphertext: envelope.ciphertext
        )

        // ChaCha20-Poly1305 authentication will fail with wrong nonce
        #expect(throws: Error.self) {
            _ = try MessageEncryptor.decrypt(
                envelope: tamperedEnvelope,
                recipientPrivateKey: recipientKey
            )
        }
    }
}
