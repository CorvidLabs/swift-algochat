@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Cross-Protocol Tests (Standard + PSK Coexistence)")
struct CrossProtocolTests {

    // MARK: - Standard Mode Unaffected

    @Test("Standard mode encrypt/decrypt still works after v1.1 code changes")
    func testStandardModeWorks() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let message = "Standard mode message"
        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipient
        )
        #expect(decrypted?.text == message)
    }

    @Test("Standard mode reply still works after v1.1 code changes")
    func testStandardModeReplyWorks() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply text",
            replyTo: (txid: "TX123", preview: "Original"),
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipient
        )
        #expect(decrypted?.text == "Reply text")
        #expect(decrypted?.replyToId == "TX123")
    }

    @Test("Standard sender decryption still works")
    func testStandardSenderDecryption() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let message = "Sender should decrypt"
        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: sender
        )
        #expect(decrypted?.text == message)
    }

    // MARK: - ChatEnvelope Rejects PSK Protocol

    @Test("ChatEnvelope.decode rejects protocol 0x02")
    func testChatEnvelopeRejectsPSK() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        let pskEnvelope = try MessageEncryptor.encryptPSK(
            message: "PSK message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let encoded = pskEnvelope.encode()

        // ChatEnvelope.decode should reject protocol 0x02
        #expect(throws: ChatError.self) {
            _ = try ChatEnvelope.decode(from: encoded)
        }
    }

    // MARK: - Coexistence

    @Test("PSK and standard messages coexist - both decode correctly")
    func testCoexistence() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        // Create standard envelope
        let standardEnvelope = try MessageEncryptor.encrypt(
            message: "Standard message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        // Create PSK envelope
        let pskEnvelope = try MessageEncryptor.encryptPSK(
            message: "PSK message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        // Both are chat messages
        let standardEncoded = standardEnvelope.encode()
        let pskEncoded = pskEnvelope.encode()

        #expect(EnvelopeDecoder.isChatMessage(standardEncoded))
        #expect(EnvelopeDecoder.isChatMessage(pskEncoded))

        // Decode each correctly
        let decodedStandard = try EnvelopeDecoder.decode(from: standardEncoded)
        let decodedPSK = try EnvelopeDecoder.decode(from: pskEncoded)

        switch decodedStandard {
        case .standard(let env):
            let decrypted = try MessageEncryptor.decrypt(
                envelope: env,
                recipientPrivateKey: recipient
            )
            #expect(decrypted?.text == "Standard message")
        case .psk:
            Issue.record("Expected standard, got PSK")
        }

        switch decodedPSK {
        case .psk(let env):
            let decrypted = try MessageEncryptor.decryptPSK(
                envelope: env,
                recipientPrivateKey: recipient,
                currentPSK: currentPSK
            )
            #expect(decrypted?.text == "PSK message")
        case .standard:
            Issue.record("Expected PSK, got standard")
        }
    }

    // MARK: - Protocol Bytes

    @Test("Standard envelope has protocol byte 0x01")
    func testStandardProtocolByte() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Test",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )
        let encoded = envelope.encode()
        #expect(encoded[1] == 0x01)
    }

    @Test("PSK envelope has protocol byte 0x02")
    func testPSKProtocolByte() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: "Test",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )
        let encoded = envelope.encode()
        #expect(encoded[1] == 0x02)
    }

    // MARK: - Multiple Messages Mixed

    @Test("Interleaved standard and PSK messages all decrypt correctly")
    func testInterleavedMessages() throws {
        let alice = Curve25519.KeyAgreement.PrivateKey()
        let bob = Curve25519.KeyAgreement.PrivateKey()
        let initialPSK = Data(repeating: 0xAA, count: 32)

        struct StoredEnvelope {
            let data: Data
            let expectedText: String
        }

        var envelopes: [StoredEnvelope] = []

        // Send alternating standard and PSK messages
        for i in 0..<20 {
            let isAlice = i % 2 == 0
            let sender = isAlice ? alice : bob
            let recipient = isAlice ? bob : alice
            let text = "Message \(i)"

            if i % 3 == 0 {
                // PSK mode
                let counter = UInt32(i / 3)
                let currentPSK = PSKRatchet.derivePSKAtCounter(
                    initialPSK: initialPSK, counter: counter
                )
                let envelope = try MessageEncryptor.encryptPSK(
                    message: text,
                    senderPrivateKey: sender,
                    recipientPublicKey: recipient.publicKey,
                    currentPSK: currentPSK,
                    ratchetCounter: counter
                )
                envelopes.append(StoredEnvelope(data: envelope.encode(), expectedText: text))
            } else {
                // Standard mode
                let envelope = try MessageEncryptor.encrypt(
                    message: text,
                    senderPrivateKey: sender,
                    recipientPublicKey: recipient.publicKey
                )
                envelopes.append(StoredEnvelope(data: envelope.encode(), expectedText: text))
            }
        }

        // Decrypt all
        for (i, stored) in envelopes.enumerated() {
            let isAlice = i % 2 == 0
            let recipientKey = isAlice ? bob : alice
            let decoded = try EnvelopeDecoder.decode(from: stored.data)

            switch decoded {
            case .standard(let env):
                let decrypted = try MessageEncryptor.decrypt(
                    envelope: env,
                    recipientPrivateKey: recipientKey
                )
                #expect(decrypted?.text == stored.expectedText,
                    "Standard message \(i) decrypted incorrectly")
            case .psk(let env):
                let counter = UInt32(i / 3)
                let currentPSK = PSKRatchet.derivePSKAtCounter(
                    initialPSK: initialPSK, counter: counter
                )
                let decrypted = try MessageEncryptor.decryptPSK(
                    envelope: env,
                    recipientPrivateKey: recipientKey,
                    currentPSK: currentPSK
                )
                #expect(decrypted?.text == stored.expectedText,
                    "PSK message \(i) decrypted incorrectly")
            }
        }
    }
}
