@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("PSK Envelope Tests")
struct PSKEnvelopeTests {

    // MARK: - Encode/Decode Round-Trip

    @Test("Encode and decode round-trip preserves all fields")
    func testEncodeDecode() throws {
        let envelope = PSKEnvelope(
            ratchetCounter: 42,
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            nonce: Data(repeating: 0x03, count: 12),
            encryptedSenderKey: Data(repeating: 0x04, count: 48),
            ciphertext: Data(repeating: 0x05, count: 20)
        )

        let encoded = envelope.encode()
        let decoded = try PSKEnvelope.decode(from: encoded)

        #expect(decoded.ratchetCounter == 42)
        #expect(decoded.senderPublicKey == Data(repeating: 0x01, count: 32))
        #expect(decoded.ephemeralPublicKey == Data(repeating: 0x02, count: 32))
        #expect(decoded.nonce == Data(repeating: 0x03, count: 12))
        #expect(decoded.encryptedSenderKey == Data(repeating: 0x04, count: 48))
        #expect(decoded.ciphertext == Data(repeating: 0x05, count: 20))
    }

    // MARK: - Header Size

    @Test("Header is exactly 130 bytes")
    func testHeaderSize() {
        let envelope = PSKEnvelope(
            ratchetCounter: 0,
            senderPublicKey: Data(repeating: 0xAA, count: 32),
            ephemeralPublicKey: Data(repeating: 0xBB, count: 32),
            nonce: Data(repeating: 0xCC, count: 12),
            encryptedSenderKey: Data(repeating: 0xDD, count: 48),
            ciphertext: Data(repeating: 0xEE, count: 16)
        )

        let encoded = envelope.encode()
        // Header = 130 bytes, ciphertext = 16 bytes, total = 146
        #expect(encoded.count == 146)
        #expect(PSKEnvelope.headerSize == 130)
    }

    // MARK: - Counter Encoding

    @Test("Ratchet counter is big-endian encoded")
    func testCounterBigEndian() throws {
        let envelope = PSKEnvelope(
            ratchetCounter: 256, // 0x00000100
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            nonce: Data(repeating: 0x03, count: 12),
            encryptedSenderKey: Data(repeating: 0x04, count: 48),
            ciphertext: Data(repeating: 0x05, count: 16)
        )

        let encoded = envelope.encode()
        // Counter bytes at [2..<6]
        #expect(encoded[2] == 0x00)
        #expect(encoded[3] == 0x00)
        #expect(encoded[4] == 0x01)
        #expect(encoded[5] == 0x00)

        let decoded = try PSKEnvelope.decode(from: encoded)
        #expect(decoded.ratchetCounter == 256)
    }

    @Test("Counter zero encodes correctly")
    func testCounterZero() throws {
        let envelope = PSKEnvelope(
            ratchetCounter: 0,
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            nonce: Data(repeating: 0x03, count: 12),
            encryptedSenderKey: Data(repeating: 0x04, count: 48),
            ciphertext: Data(repeating: 0x05, count: 16)
        )

        let encoded = envelope.encode()
        #expect(encoded[2] == 0x00)
        #expect(encoded[3] == 0x00)
        #expect(encoded[4] == 0x00)
        #expect(encoded[5] == 0x00)

        let decoded = try PSKEnvelope.decode(from: encoded)
        #expect(decoded.ratchetCounter == 0)
    }

    @Test("Max counter encodes correctly")
    func testCounterMax() throws {
        let envelope = PSKEnvelope(
            ratchetCounter: UInt32.max,
            senderPublicKey: Data(repeating: 0x01, count: 32),
            ephemeralPublicKey: Data(repeating: 0x02, count: 32),
            nonce: Data(repeating: 0x03, count: 12),
            encryptedSenderKey: Data(repeating: 0x04, count: 48),
            ciphertext: Data(repeating: 0x05, count: 16)
        )

        let encoded = envelope.encode()
        let decoded = try PSKEnvelope.decode(from: encoded)
        #expect(decoded.ratchetCounter == UInt32.max)
    }

    // MARK: - Max Payload

    @Test("Max payload size is 878 bytes")
    func testMaxPayloadSize() {
        #expect(PSKEnvelope.maxPayloadSize == 878)
    }

    // MARK: - Validation

    @Test("Rejects wrong version")
    func testRejectsWrongVersion() {
        var data = Data(repeating: 0x00, count: 150)
        data[0] = 0x02  // Wrong version
        data[1] = 0x02  // PSK protocol

        #expect(throws: ChatError.self) {
            _ = try PSKEnvelope.decode(from: data)
        }
    }

    @Test("Rejects wrong protocol")
    func testRejectsWrongProtocol() {
        var data = Data(repeating: 0x00, count: 150)
        data[0] = 0x01  // Correct version
        data[1] = 0x01  // Standard protocol (not PSK)

        #expect(throws: ChatError.self) {
            _ = try PSKEnvelope.decode(from: data)
        }
    }

    @Test("Rejects data too short")
    func testRejectsDataTooShort() {
        let data = Data([0x01, 0x02, 0x00, 0x00])  // Only 4 bytes

        #expect(throws: ChatError.self) {
            _ = try PSKEnvelope.decode(from: data)
        }
    }

    @Test("Rejects data shorter than minimum (146 bytes)")
    func testRejectsShortData() {
        // 130 header + 16 tag = 146 minimum
        var data = Data(repeating: 0x00, count: 145)
        data[0] = 0x01
        data[1] = 0x02

        #expect(throws: ChatError.self) {
            _ = try PSKEnvelope.decode(from: data)
        }
    }

    // MARK: - Protocol Spec Test Vector

    @Test("Minimal PSK envelope matches protocol spec (Test Case 4.5)")
    func testProtocolSpecEnvelope() throws {
        let envelope = PSKEnvelope(
            ratchetCounter: 0,
            senderPublicKey: Data(repeating: 0xAA, count: 32),
            ephemeralPublicKey: Data(repeating: 0xBB, count: 32),
            nonce: Data(repeating: 0xCC, count: 12),
            encryptedSenderKey: Data(repeating: 0xDD, count: 48),
            ciphertext: Data(repeating: 0xEE, count: 16)
        )

        let encoded = envelope.encode()

        // Verify version + protocol
        #expect(encoded[0] == 0x01)
        #expect(encoded[1] == 0x02)

        // Verify counter (4 bytes of zero)
        #expect(encoded[2..<6] == Data([0x00, 0x00, 0x00, 0x00]))

        // Verify total size
        #expect(encoded.count == 146)

        // Round-trip
        let decoded = try PSKEnvelope.decode(from: encoded)
        #expect(decoded.ratchetCounter == 0)
        #expect(decoded.senderPublicKey == Data(repeating: 0xAA, count: 32))
        #expect(decoded.ephemeralPublicKey == Data(repeating: 0xBB, count: 32))
    }
}
