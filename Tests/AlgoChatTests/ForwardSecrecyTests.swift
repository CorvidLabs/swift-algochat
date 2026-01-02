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

@Suite("ChatEnvelope V2 Tests")
struct ChatEnvelopeV2Tests {
    @Test("V2 envelope has correct version")
    func testV2Version() {
        let envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            nonce: Data(repeating: 0x03, count: 12),
            ciphertext: Data(repeating: 0x04, count: 50)
        )

        #expect(envelope.envelopeVersion == ChatEnvelope.versionV2)
        #expect(envelope.usesForwardSecrecy == true)
    }

    @Test("V1 envelope does not use forward secrecy")
    func testV1NoForwardSecrecy() {
        let envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            nonce: Data(repeating: 0x02, count: 12),
            ciphertext: Data(repeating: 0x03, count: 50)
        )

        #expect(envelope.envelopeVersion == ChatEnvelope.versionV1)
        #expect(envelope.usesForwardSecrecy == false)
        #expect(envelope.ephemeralPublicKey == nil)
    }

    @Test("V2 envelope encodes correctly")
    func testV2Encode() {
        let senderKey = Data(repeating: 0x01, count: 32)
        let ephemeralKey = Data(repeating: 0x02, count: 32)
        let nonce = Data(repeating: 0x03, count: 12)
        let ciphertext = Data(repeating: 0x04, count: 50)

        let envelope = ChatEnvelope(
            senderPublicKey: senderKey,
            ephemeralPublicKey: ephemeralKey,
            nonce: nonce,
            ciphertext: ciphertext
        )

        let encoded = envelope.encode()

        #expect(encoded[0] == ChatEnvelope.versionV2)
        #expect(encoded[1] == ChatEnvelope.protocolID)
        #expect(Data(encoded[2..<34]) == senderKey)
        #expect(Data(encoded[34..<66]) == ephemeralKey)
        #expect(Data(encoded[66..<78]) == nonce)
        #expect(Data(encoded[78...]) == ciphertext)
    }

    @Test("V2 envelope decode round trip")
    func testV2DecodeRoundTrip() throws {
        let original = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            nonce: Data(repeating: 0x03, count: 12),
            ciphertext: Data(repeating: 0x04, count: 50)
        )

        let encoded = original.encode()
        let decoded = try ChatEnvelope.decode(from: encoded)

        #expect(decoded.envelopeVersion == original.envelopeVersion)
        #expect(decoded.senderPublicKey == original.senderPublicKey)
        #expect(decoded.ephemeralPublicKey == original.ephemeralPublicKey)
        #expect(decoded.nonce == original.nonce)
        #expect(decoded.ciphertext == original.ciphertext)
    }

    @Test("V1 envelope decode round trip")
    func testV1DecodeRoundTrip() throws {
        let original = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            nonce: Data(repeating: 0x02, count: 12),
            ciphertext: Data(repeating: 0x03, count: 50)
        )

        let encoded = original.encode()
        let decoded = try ChatEnvelope.decode(from: encoded)

        #expect(decoded.envelopeVersion == ChatEnvelope.versionV1)
        #expect(decoded.senderPublicKey == original.senderPublicKey)
        #expect(decoded.ephemeralPublicKey == nil)
        #expect(decoded.nonce == original.nonce)
        #expect(decoded.ciphertext == original.ciphertext)
    }

    @Test("V2 header size is correct")
    func testV2HeaderSize() {
        // V2: version(1) + protocol(1) + sender(32) + ephemeral(32) + nonce(12) = 78
        #expect(ChatEnvelope.headerSizeV2 == 78)
    }

    @Test("V1 header size is correct")
    func testV1HeaderSize() {
        // V1: version(1) + protocol(1) + sender(32) + nonce(12) = 46
        #expect(ChatEnvelope.headerSizeV1 == 46)
    }

    @Test("Max payload sizes are correct")
    func testMaxPayloadSizes() {
        // 1024 byte note - header - 16 byte tag
        #expect(ChatEnvelope.maxPayloadSizeV1 == 962)
        #expect(ChatEnvelope.maxPayloadSizeV2 == 930)
    }

    @Test("Decode fails for unsupported version")
    func testDecodeUnsupportedVersion() {
        var data = Data([0x99, ChatEnvelope.protocolID])
        data.append(Data(repeating: 0x00, count: 100))

        #expect(throws: ChatError.self) {
            try ChatEnvelope.decode(from: data)
        }
    }

    @Test("Decode fails for unsupported protocol")
    func testDecodeUnsupportedProtocol() {
        var data = Data([ChatEnvelope.versionV2, 0x99])
        data.append(Data(repeating: 0x00, count: 100))

        #expect(throws: ChatError.self) {
            try ChatEnvelope.decode(from: data)
        }
    }

    @Test("Decode fails for data too short")
    func testDecodeDataTooShort() {
        let data = Data([ChatEnvelope.versionV2])

        #expect(throws: ChatError.self) {
            try ChatEnvelope.decode(from: data)
        }
    }
}

@Suite("V2 Encryption Tests")
struct V2EncryptionTests {
    @Test("Encrypt produces V2 envelope")
    func testEncryptProducesV2Envelope() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Hello, World!",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        #expect(envelope.envelopeVersion == ChatEnvelope.versionV2)
        #expect(envelope.usesForwardSecrecy == true)
        #expect(envelope.ephemeralPublicKey != nil)
        #expect(envelope.ephemeralPublicKey?.count == 32)
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

    @Test("V2 encrypt and decrypt round trip")
    func testV2EncryptDecryptRoundTrip() throws {
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

    @Test("V2 encrypt with reply context")
    func testV2EncryptWithReply() throws {
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

    @Test("V2 encryptRaw works correctly")
    func testV2EncryptRaw() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let data = Data("Raw data payload".utf8)

        let envelope = try MessageEncryptor.encryptRaw(
            data,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        #expect(envelope.usesForwardSecrecy == true)
        #expect(envelope.ephemeralPublicKey != nil)
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

        // Create a message larger than max payload size (930 bytes)
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

@Suite("V1 Backward Compatibility Tests")
struct V1BackwardCompatibilityTests {
    @Test("Can decrypt V1 envelope")
    func testDecryptV1Envelope() throws {
        // Create a V1-style envelope manually (simulating legacy messages)
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()
        let message = "Legacy message"

        // Manually create V1 encryption (static key ECDH)
        let sharedSecret = try senderKey.sharedSecretFromKeyAgreement(with: recipientKey.publicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("AlgoChat-v1-salt".utf8),
            sharedInfo: Data("AlgoChat-v1-message".utf8),
            outputByteCount: 32
        )

        var nonceBytes = [UInt8](repeating: 0, count: 12)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, 12, &nonceBytes)
        #else
        let urandom = FileHandle(forReadingAtPath: "/dev/urandom")!
        nonceBytes = [UInt8](urandom.readData(ofLength: 12))
        try? urandom.close()
        #endif
        let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))

        let sealedBox = try ChaChaPoly.seal(
            Data(message.utf8),
            using: symmetricKey,
            nonce: nonce
        )

        let v1Envelope = ChatEnvelope(
            senderPublicKey: senderKey.publicKey.rawRepresentation,
            nonce: Data(nonceBytes),
            ciphertext: sealedBox.ciphertext + sealedBox.tag
        )

        // Decrypt using the library
        let decrypted = try MessageEncryptor.decrypt(
            envelope: v1Envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decrypted?.text == message)
    }

    @Test("V1 and V2 envelopes detected correctly")
    func testVersionDetection() {
        let v1Envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            nonce: Data(repeating: 0x02, count: 12),
            ciphertext: Data(repeating: 0x03, count: 50)
        )

        let v2Envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            nonce: Data(repeating: 0x03, count: 12),
            ciphertext: Data(repeating: 0x04, count: 50)
        )

        #expect(v1Envelope.usesForwardSecrecy == false)
        #expect(v2Envelope.usesForwardSecrecy == true)
    }

    @Test("Mixed V1 and V2 with same key pair")
    func testMixedV1V2SameKeyPair() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Create V1 message (static key ECDH)
        let sharedSecret = try senderKey.sharedSecretFromKeyAgreement(with: recipientKey.publicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("AlgoChat-v1-salt".utf8),
            sharedInfo: Data("AlgoChat-v1-message".utf8),
            outputByteCount: 32
        )

        var nonceBytes = [UInt8](repeating: 0, count: 12)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, 12, &nonceBytes)
        #else
        let urandom2 = FileHandle(forReadingAtPath: "/dev/urandom")!
        nonceBytes = [UInt8](urandom2.readData(ofLength: 12))
        try? urandom2.close()
        #endif
        let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))

        let sealedBox = try ChaChaPoly.seal(
            Data("V1 message".utf8),
            using: symmetricKey,
            nonce: nonce
        )

        let v1Envelope = ChatEnvelope(
            senderPublicKey: senderKey.publicKey.rawRepresentation,
            nonce: Data(nonceBytes),
            ciphertext: sealedBox.ciphertext + sealedBox.tag
        )

        // Create V2 message (ephemeral key ECDH) with SAME sender key
        let v2Envelope = try MessageEncryptor.encrypt(
            message: "V2 message",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Decrypt both
        let decryptedV1 = try MessageEncryptor.decrypt(
            envelope: v1Envelope,
            recipientPrivateKey: recipientKey
        )
        let decryptedV2 = try MessageEncryptor.decrypt(
            envelope: v2Envelope,
            recipientPrivateKey: recipientKey
        )

        #expect(decryptedV1?.text == "V1 message")
        #expect(decryptedV2?.text == "V2 message")
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
        var tamperedEphemeralKey = envelope.ephemeralPublicKey!
        tamperedEphemeralKey[0] ^= 0xFF  // Flip bits

        let tamperedEnvelope = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: tamperedEphemeralKey,
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
            nonce: Data(repeating: 0x03, count: 12),
            ciphertext: Data(repeating: 0x04, count: 10)  // Only 10 bytes, need at least 16
        )

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: recipientKey
            )
        }
    }

    @Test("Boundary size message at exactly V2 max")
    func testBoundarySizeV2Max() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // V2 max payload is 930 bytes
        let maxMessage = String(repeating: "A", count: 930)

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

    @Test("Boundary size message one byte under V2 max")
    func testBoundarySizeOneUnderMax() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // One byte under V2 max
        let message = String(repeating: "B", count: 929)

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
            ephemeralPublicKey: envelope.ephemeralPublicKey!,
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
            ephemeralPublicKey: envelope.ephemeralPublicKey!,
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
