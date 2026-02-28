@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("ChatError Tests")
struct ChatErrorTests {
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() throws {
        let errors: [(ChatError, String)] = [
            (.messageTooLarge(maxSize: 962), "962"),
            (.decryptionFailed("test reason"), "test reason"),
            (.encodingFailed("UTF-8 error"), "UTF-8 error"),
            (.randomGenerationFailed, "random"),
            (.invalidPublicKey("bad key"), "bad key"),
            (.keyDerivationFailed("derivation error"), "derivation error"),
            (.invalidEnvelope("corrupt data"), "corrupt data"),
            (.unsupportedVersion(99), "99"),
            (.unsupportedProtocol(99), "99"),
            (.indexerNotConfigured, "Indexer"),
            (.publicKeyNotFound("ADDR123"), "ADDR123"),
            (.invalidRecipient("bad addr"), "bad addr"),
            (.transactionFailed("tx error"), "tx error"),
            (.insufficientBalance(required: 1000, available: 500), "1000"),
        ]

        for (error, expectedSubstring) in errors {
            let description = error.errorDescription ?? ""
            #expect(
                description.contains(expectedSubstring),
                "Expected '\(expectedSubstring)' in '\(description)'"
            )
        }
    }

    @Test("ChatError conforms to LocalizedError")
    func testLocalizedErrorConformance() {
        let error: any LocalizedError = ChatError.messageTooLarge(maxSize: 100)
        #expect(error.errorDescription != nil)
    }

    @Test("ChatError is Sendable")
    func testSendableConformance() async {
        let error: any Sendable = ChatError.decryptionFailed("test")
        await Task {
            // Verify we can send across task boundaries
            _ = error
        }.value
    }
}

@Suite("Error Recovery Tests", .serialized)
struct ErrorRecoveryTests {
    @Test("Malformed envelope data throws appropriate error")
    func testMalformedEnvelopeError() throws {
        let malformedData = Data([0x01, 0x01])  // Too short

        #expect(throws: ChatError.self) {
            _ = try ChatEnvelope.decode(from: malformedData)
        }
    }

    @Test("Invalid version byte throws unsupportedVersion")
    func testInvalidVersionError() throws {
        // Create data with wrong version
        var data = Data(count: 100)
        data[0] = 0xFF  // Wrong version
        data[1] = ChatEnvelope.protocolID

        do {
            _ = try ChatEnvelope.decode(from: data)
            Issue.record("Expected error to be thrown")
        } catch let error as ChatError {
            if case .unsupportedVersion(let v) = error {
                #expect(v == 0xFF)
            } else {
                Issue.record("Expected unsupportedVersion error, got \(error)")
            }
        }
    }

    @Test("Invalid protocol byte throws unsupportedProtocol")
    func testInvalidProtocolError() throws {
        // Create data with wrong protocol
        var data = Data(count: 100)
        data[0] = ChatEnvelope.version
        data[1] = 0xFF  // Wrong protocol

        do {
            _ = try ChatEnvelope.decode(from: data)
            Issue.record("Expected error to be thrown")
        } catch let error as ChatError {
            if case .unsupportedProtocol(let p) = error {
                #expect(p == 0xFF)
            } else {
                Issue.record("Expected unsupportedProtocol error, got \(error)")
            }
        }
    }

    @Test("Empty public key data throws invalidPublicKey")
    func testEmptyPublicKeyError() throws {
        let emptyData = Data()

        #expect(throws: ChatError.self) {
            _ = try KeyDerivation.decodePublicKey(from: emptyData)
        }
    }

    @Test("Wrong size public key throws invalidPublicKey")
    func testWrongSizePublicKeyError() throws {
        let wrongSize = Data(repeating: 0x01, count: 16)  // Should be 32

        do {
            _ = try KeyDerivation.decodePublicKey(from: wrongSize)
            Issue.record("Expected error to be thrown")
        } catch let error as ChatError {
            if case .invalidPublicKey = error {
                // Expected
            } else {
                Issue.record("Expected invalidPublicKey error, got \(error)")
            }
        }
    }

    @Test("Decryption with tampered ciphertext fails")
    func testTamperedCiphertextError() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Original message",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Tamper with ciphertext
        var tamperedCiphertext = envelope.ciphertext
        if !tamperedCiphertext.isEmpty {
            tamperedCiphertext[0] ^= 0xFF
        }

        let tamperedEnvelope = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            encryptedSenderKey: envelope.encryptedSenderKey,
            nonce: envelope.nonce,
            ciphertext: tamperedCiphertext
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decrypt(
                envelope: tamperedEnvelope,
                recipientPrivateKey: recipientKey
            )
        }
    }

    @Test("Decryption with tampered nonce fails")
    func testTamperedNonceError() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Original message",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        // Tamper with nonce
        var tamperedNonce = envelope.nonce
        if !tamperedNonce.isEmpty {
            tamperedNonce[0] ^= 0xFF
        }

        let tamperedEnvelope = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            encryptedSenderKey: envelope.encryptedSenderKey,
            nonce: tamperedNonce,
            ciphertext: envelope.ciphertext
        )

        #expect(throws: (any Error).self) {
            _ = try MessageEncryptor.decrypt(
                envelope: tamperedEnvelope,
                recipientPrivateKey: recipientKey
            )
        }
    }
}
