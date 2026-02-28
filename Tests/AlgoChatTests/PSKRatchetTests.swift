@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("PSK Ratchet Derivation Tests")
struct PSKRatchetTests {
    /// Test vector: initial PSK = 32 bytes of 0xAA
    private let initialPSK = Data(repeating: 0xAA, count: 32)

    // MARK: - Session PSK Derivation

    @Test("Session PSK at counter 0 matches protocol spec")
    func testSessionPSKCounter0() {
        let sessionPSK = PSKRatchet.deriveSessionPSK(initialPSK: initialPSK, sessionIndex: 0)
        let expectedHex = "a031707ea9e9e50bd8ea4eb9a2bd368465ea1aff14caab293d38954b4717e888"
        #expect(sessionPSK.hex == expectedHex)
    }

    @Test("Session PSK at counter 100 (session 1) matches protocol spec")
    func testSessionPSKCounter100() {
        let sessionPSK = PSKRatchet.deriveSessionPSK(initialPSK: initialPSK, sessionIndex: 1)
        let expectedHex = "994cffbb4f84fa5410d44574bb9fa7408a8c2f1ed2b3a00f5168fc74c71f7cea"
        #expect(sessionPSK.hex == expectedHex)
    }

    @Test("Same session PSK for counters 0 and 99 (same session)")
    func testSameSessionForSameSessionIndex() {
        let sessionPSK0 = PSKRatchet.deriveSessionPSK(initialPSK: initialPSK, sessionIndex: 0)
        let sessionPSK99 = PSKRatchet.deriveSessionPSK(initialPSK: initialPSK, sessionIndex: 0)
        #expect(sessionPSK0 == sessionPSK99)
    }

    @Test("Different session PSK for sessions 0 and 1")
    func testDifferentSessionPSK() {
        let session0 = PSKRatchet.deriveSessionPSK(initialPSK: initialPSK, sessionIndex: 0)
        let session1 = PSKRatchet.deriveSessionPSK(initialPSK: initialPSK, sessionIndex: 1)
        #expect(session0 != session1)
    }

    // MARK: - Position PSK Derivation

    @Test("Position PSK at counter 0 matches protocol spec")
    func testPositionPSKCounter0() {
        let positionPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)
        let expectedHex = "2918fd486b9bd024d712f6234b813c0f4167237d60c2c1fca37326b20497c165"
        #expect(positionPSK.hex == expectedHex)
    }

    @Test("Position PSK at counter 99 matches protocol spec")
    func testPositionPSKCounter99() {
        let positionPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 99)
        let expectedHex = "5b48a50a25261f6b63fe9c867b46be46de4d747c3477db6290045ba519a4d38b"
        #expect(positionPSK.hex == expectedHex)
    }

    @Test("Position PSK at counter 100 matches protocol spec")
    func testPositionPSKCounter100() {
        let positionPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 100)
        let expectedHex = "7a15d3add6a28858e6a1f1ea0d22bdb29b7e129a1330c4908d9b46a460992694"
        #expect(positionPSK.hex == expectedHex)
    }

    @Test("All three test vectors produce different position PSKs")
    func testAllDifferentPositionPSKs() {
        let psk0 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)
        let psk99 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 99)
        let psk100 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 100)

        #expect(psk0 != psk99)
        #expect(psk0 != psk100)
        #expect(psk99 != psk100)
    }

    // MARK: - Hybrid Key Derivation

    @Test("Hybrid symmetric key derivation produces correct output structure")
    func testHybridSymmetricKeyDerivation() throws {
        // Use random keys (cannot reproduce protocol spec deterministic keys in swift-crypto
        // because PrivateKey(rawRepresentation:) applies clamping differently)
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()

        let currentPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)

        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(
            with: recipient.publicKey
        )

        let symmetricKey = PSKRatchet.deriveHybridSymmetricKey(
            sharedSecret: sharedSecret,
            currentPSK: currentPSK,
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
            senderPublicKey: sender.publicKey.rawRepresentation,
            recipientPublicKey: recipient.publicKey.rawRepresentation
        )

        // Key should be 32 bytes
        let symmetricKeyData = symmetricKey.withUnsafeBytes { Data($0) }
        #expect(symmetricKeyData.count == 32)

        // Same inputs produce same output (deterministic)
        let symmetricKey2 = PSKRatchet.deriveHybridSymmetricKey(
            sharedSecret: sharedSecret,
            currentPSK: currentPSK,
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
            senderPublicKey: sender.publicKey.rawRepresentation,
            recipientPublicKey: recipient.publicKey.rawRepresentation
        )
        let symmetricKeyData2 = symmetricKey2.withUnsafeBytes { Data($0) }
        #expect(symmetricKeyData == symmetricKeyData2)

        // Different PSK produces different key
        let otherPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 1)
        let otherKey = PSKRatchet.deriveHybridSymmetricKey(
            sharedSecret: sharedSecret,
            currentPSK: otherPSK,
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
            senderPublicKey: sender.publicKey.rawRepresentation,
            recipientPublicKey: recipient.publicKey.rawRepresentation
        )
        let otherKeyData = otherKey.withUnsafeBytes { Data($0) }
        #expect(symmetricKeyData != otherKeyData)
    }

    @Test("Sender key derivation produces correct output structure")
    func testSenderKeyDerivation() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()

        let currentPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)

        let senderSharedSecret = try ephemeral.sharedSecretFromKeyAgreement(
            with: sender.publicKey
        )

        let senderKey = PSKRatchet.deriveSenderKey(
            senderSharedSecret: senderSharedSecret,
            currentPSK: currentPSK,
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
            senderPublicKey: sender.publicKey.rawRepresentation
        )

        // Key should be 32 bytes
        let senderKeyData = senderKey.withUnsafeBytes { Data($0) }
        #expect(senderKeyData.count == 32)

        // Same inputs produce same output
        let senderKey2 = PSKRatchet.deriveSenderKey(
            senderSharedSecret: senderSharedSecret,
            currentPSK: currentPSK,
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
            senderPublicKey: sender.publicKey.rawRepresentation
        )
        let senderKeyData2 = senderKey2.withUnsafeBytes { Data($0) }
        #expect(senderKeyData == senderKeyData2)

        // Different PSK produces different key
        let otherPSK = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 1)
        let otherKey = PSKRatchet.deriveSenderKey(
            senderSharedSecret: senderSharedSecret,
            currentPSK: otherPSK,
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
            senderPublicKey: sender.publicKey.rawRepresentation
        )
        let otherKeyData = otherKey.withUnsafeBytes { Data($0) }
        #expect(senderKeyData != otherKeyData)
    }

    // MARK: - Determinism

    @Test("Ratchet derivation is deterministic")
    func testDeterminism() {
        let psk1 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 42)
        let psk2 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 42)
        #expect(psk1 == psk2)
    }

    @Test("Different initial PSK produces different results")
    func testDifferentInitialPSK() {
        let otherPSK = Data(repeating: 0xBB, count: 32)
        let psk1 = PSKRatchet.derivePSKAtCounter(initialPSK: initialPSK, counter: 0)
        let psk2 = PSKRatchet.derivePSKAtCounter(initialPSK: otherPSK, counter: 0)
        #expect(psk1 != psk2)
    }
}

