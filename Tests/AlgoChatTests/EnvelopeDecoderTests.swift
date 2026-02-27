@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Envelope Decoder Tests", .serialized)
struct EnvelopeDecoderTests {

    // MARK: - Standard Envelope

    @Test("Standard envelope decodes as .standard")
    func testStandardDecode() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Standard message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let encoded = envelope.encode()
        let decoded = try EnvelopeDecoder.decode(from: encoded)

        switch decoded {
        case .standard(let e):
            #expect(e.senderPublicKey == envelope.senderPublicKey)
        case .psk:
            Issue.record("Expected standard envelope, got PSK")
        }
    }

    // MARK: - PSK Envelope

    @Test("PSK envelope decodes as .psk")
    func testPSKDecode() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: Data(repeating: 0xAA, count: 32), counter: 0
        )

        let envelope = try MessageEncryptor.encryptPSK(
            message: "PSK message",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey,
            currentPSK: currentPSK,
            ratchetCounter: 0
        )

        let encoded = envelope.encode()
        let decoded = try EnvelopeDecoder.decode(from: encoded)

        switch decoded {
        case .standard:
            Issue.record("Expected PSK envelope, got standard")
        case .psk(let e):
            #expect(e.ratchetCounter == 0)
            #expect(e.senderPublicKey == sender.publicKey.rawRepresentation)
        }
    }

    // MARK: - isChatMessage

    @Test("isChatMessage returns true for standard envelope")
    func testIsChatMessageStandard() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Test",
            senderPrivateKey: sender,
            recipientPublicKey: recipient.publicKey
        )

        let encoded = envelope.encode()
        #expect(EnvelopeDecoder.isChatMessage(encoded))
    }

    @Test("isChatMessage returns true for PSK envelope")
    func testIsChatMessagePSK() throws {
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
        #expect(EnvelopeDecoder.isChatMessage(encoded))
    }

    @Test("isChatMessage returns false for unknown protocol")
    func testIsChatMessageUnknown() {
        var data = Data(repeating: 0x00, count: 150)
        data[0] = 0x01
        data[1] = 0x03 // Unknown protocol
        #expect(!EnvelopeDecoder.isChatMessage(data))
    }

    @Test("isChatMessage returns false for too-short data")
    func testIsChatMessageTooShort() {
        #expect(!EnvelopeDecoder.isChatMessage(Data()))
        #expect(!EnvelopeDecoder.isChatMessage(Data([0x01])))
    }

    @Test("isChatMessage returns false for wrong version")
    func testIsChatMessageWrongVersion() {
        var data = Data(repeating: 0x00, count: 150)
        data[0] = 0x02 // Wrong version
        data[1] = 0x01
        #expect(!EnvelopeDecoder.isChatMessage(data))
    }

    // MARK: - Error Cases

    @Test("Unknown protocol throws unsupportedProtocol")
    func testUnknownProtocol() {
        var data = Data(repeating: 0x00, count: 150)
        data[0] = 0x01
        data[1] = 0x03

        #expect(throws: ChatError.self) {
            _ = try EnvelopeDecoder.decode(from: data)
        }
    }

    @Test("Empty data throws error")
    func testEmptyData() {
        #expect(throws: ChatError.self) {
            _ = try EnvelopeDecoder.decode(from: Data())
        }
    }
}
