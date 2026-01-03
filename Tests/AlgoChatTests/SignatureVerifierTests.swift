import Algorand
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("SignatureVerifier Tests")
struct SignatureVerifierTests {
    @Test("Sign and verify round trip succeeds")
    func testSignAndVerifyRoundTrip() throws {
        let account = try Account()
        let encryptionKey = Curve25519.KeyAgreement.PrivateKey()
        let encryptionPublicKey = encryptionKey.publicKey.rawRepresentation

        let signature = try SignatureVerifier.sign(
            encryptionPublicKey: encryptionPublicKey,
            with: account
        )

        #expect(signature.count == SignatureVerifier.signatureSize)

        let isValid = try SignatureVerifier.verify(
            encryptionPublicKey: encryptionPublicKey,
            signedBy: account.address,
            signature: signature
        )

        #expect(isValid == true)
    }

    @Test("Verification with wrong address fails")
    func testVerificationWithWrongAddressFails() throws {
        let signer = try Account()
        let wrongAccount = try Account()
        let encryptionKey = Curve25519.KeyAgreement.PrivateKey()
        let encryptionPublicKey = encryptionKey.publicKey.rawRepresentation

        let signature = try SignatureVerifier.sign(
            encryptionPublicKey: encryptionPublicKey,
            with: signer
        )

        let isValid = try SignatureVerifier.verify(
            encryptionPublicKey: encryptionPublicKey,
            signedBy: wrongAccount.address,
            signature: signature
        )

        #expect(isValid == false)
    }

    @Test("Verification with wrong key fails")
    func testVerificationWithWrongKeyFails() throws {
        let account = try Account()
        let encryptionKey1 = Curve25519.KeyAgreement.PrivateKey()
        let encryptionKey2 = Curve25519.KeyAgreement.PrivateKey()

        let signature = try SignatureVerifier.sign(
            encryptionPublicKey: encryptionKey1.publicKey.rawRepresentation,
            with: account
        )

        let isValid = try SignatureVerifier.verify(
            encryptionPublicKey: encryptionKey2.publicKey.rawRepresentation,
            signedBy: account.address,
            signature: signature
        )

        #expect(isValid == false)
    }

    @Test("Signing with invalid key size throws")
    func testSigningWithInvalidKeySizeThrows() throws {
        let account = try Account()
        let invalidKey = Data(repeating: 0x01, count: 16)

        #expect(throws: ChatError.self) {
            _ = try SignatureVerifier.sign(
                encryptionPublicKey: invalidKey,
                with: account
            )
        }
    }

    @Test("Verification with invalid signature size throws")
    func testVerificationWithInvalidSignatureSizeThrows() throws {
        let account = try Account()
        let encryptionKey = Curve25519.KeyAgreement.PrivateKey()
        let invalidSignature = Data(repeating: 0x00, count: 32)

        #expect(throws: ChatError.self) {
            _ = try SignatureVerifier.verify(
                encryptionPublicKey: encryptionKey.publicKey.rawRepresentation,
                signedBy: account.address,
                signature: invalidSignature
            )
        }
    }

    @Test("Fingerprint generates consistent output")
    func testFingerprintConsistency() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let publicKeyData = key.publicKey.rawRepresentation

        let fingerprint1 = SignatureVerifier.fingerprint(of: publicKeyData)
        let fingerprint2 = SignatureVerifier.fingerprint(of: publicKeyData)

        #expect(fingerprint1 == fingerprint2)
    }

    @Test("Fingerprint has correct format")
    func testFingerprintFormat() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let publicKeyData = key.publicKey.rawRepresentation

        let fingerprint = SignatureVerifier.fingerprint(of: publicKeyData)

        // Should be 4 groups of 4 hex chars separated by spaces: "XXXX XXXX XXXX XXXX"
        let groups = fingerprint.split(separator: " ")
        #expect(groups.count == 4)

        for group in groups {
            #expect(group.count == 4)
            #expect(group.allSatisfy { $0.isHexDigit })
        }
    }

    @Test("Different keys produce different fingerprints")
    func testDifferentKeysProduceDifferentFingerprints() throws {
        let key1 = Curve25519.KeyAgreement.PrivateKey()
        let key2 = Curve25519.KeyAgreement.PrivateKey()

        let fingerprint1 = SignatureVerifier.fingerprint(of: key1.publicKey.rawRepresentation)
        let fingerprint2 = SignatureVerifier.fingerprint(of: key2.publicKey.rawRepresentation)

        #expect(fingerprint1 != fingerprint2)
    }
}

@Suite("V3 Envelope Tests")
struct V3EnvelopeTests {
    @Test("V3 envelope encodes and decodes correctly")
    func testV3EnvelopeEncodeDecode() throws {
        let senderKey = Data(repeating: 0x01, count: 32)
        let ephemeralKey = Data(repeating: 0x02, count: 32)
        let signature = Data(repeating: 0x03, count: 64)
        let nonce = Data(repeating: 0x04, count: 12)
        let ciphertext = Data(repeating: 0x05, count: 50)

        let envelope = ChatEnvelope(
            senderPublicKey: senderKey,
            ephemeralPublicKey: ephemeralKey,
            signature: signature,
            nonce: nonce,
            ciphertext: ciphertext
        )

        #expect(envelope.envelopeVersion == ChatEnvelope.versionV3)
        #expect(envelope.hasSignature == true)

        let encoded = envelope.encode()
        let decoded = try ChatEnvelope.decode(from: encoded)

        #expect(decoded.envelopeVersion == ChatEnvelope.versionV3)
        #expect(decoded.senderPublicKey == senderKey)
        #expect(decoded.ephemeralPublicKey == ephemeralKey)
        #expect(decoded.signature == signature)
        #expect(decoded.nonce == nonce)
        #expect(decoded.ciphertext == ciphertext)
        #expect(decoded.hasSignature == true)
        #expect(decoded.usesForwardSecrecy == true)
    }

    @Test("V3 envelope has correct header size")
    func testV3HeaderSize() throws {
        let envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0, count: 32),
            ephemeralPublicKey: Data(repeating: 0, count: 32),
            signature: Data(repeating: 0, count: 64),
            nonce: Data(repeating: 0, count: 12),
            ciphertext: Data(repeating: 0, count: 20)
        )

        let encoded = envelope.encode()

        // V3 header: version(1) + protocol(1) + static(32) + ephemeral(32) + signature(64) + nonce(12) = 142
        #expect(encoded.count == ChatEnvelope.headerSizeV3 + 20)
        #expect(encoded[0] == ChatEnvelope.versionV3)
        #expect(encoded[1] == ChatEnvelope.protocolID)
    }

    @Test("encryptWithSignature produces V3 envelope")
    func testEncryptWithSignatureProducesV3() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let signature = Data(repeating: 0x42, count: 64)

        let envelope = try MessageEncryptor.encryptWithSignature(
            Data("test".utf8),
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey,
            signature: signature
        )

        #expect(envelope.envelopeVersion == ChatEnvelope.versionV3)
        #expect(envelope.hasSignature == true)
        #expect(envelope.signature == signature)
    }

    @Test("V3 envelope can be decrypted")
    func testV3EnvelopeDecryption() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let signature = Data(repeating: 0x42, count: 64)

        let message = "Hello from V3!"
        let envelope = try MessageEncryptor.encryptWithSignature(
            Data(message.utf8),
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPrivateKey.publicKey,
            signature: signature
        )

        // Decrypt should work with V3 envelope (signature is metadata only)
        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.text == message)
    }

    @Test("V3 envelope respects smaller payload limit")
    func testV3PayloadLimit() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let signature = Data(repeating: 0x42, count: 64)

        // V3 max payload is smaller due to signature overhead
        let tooLarge = Data(repeating: 0x00, count: ChatEnvelope.maxPayloadSizeV3 + 1)

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.encryptWithSignature(
                tooLarge,
                senderPrivateKey: senderPrivateKey,
                recipientPublicKey: recipientPrivateKey.publicKey,
                signature: signature
            )
        }
    }

    @Test("V3 envelope rejects invalid signature size")
    func testV3RejectsInvalidSignatureSize() throws {
        let senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let invalidSignature = Data(repeating: 0x42, count: 32)

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.encryptWithSignature(
                Data("test".utf8),
                senderPrivateKey: senderPrivateKey,
                recipientPublicKey: recipientPrivateKey.publicKey,
                signature: invalidSignature
            )
        }
    }
}
