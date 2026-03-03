@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("DiscoveredKey Tests")
struct DiscoveredKeyTests {
    @Test("Unverified key has isVerified false")
    func testUnverifiedKey() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let discovered = DiscoveredKey(publicKey: key.publicKey, isVerified: false)

        #expect(discovered.isVerified == false)
        #expect(discovered.publicKey.rawRepresentation == key.publicKey.rawRepresentation)
    }

    @Test("Verified key has isVerified true")
    func testVerifiedKey() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let discovered = DiscoveredKey(publicKey: key.publicKey, isVerified: true)

        #expect(discovered.isVerified == true)
    }

    @Test("Keys from different sources preserve verification status")
    func testVerificationStatusPreserved() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()

        let unverified = DiscoveredKey(publicKey: key.publicKey, isVerified: false)
        let verified = DiscoveredKey(publicKey: key.publicKey, isVerified: true)

        // Same key, different verification status
        #expect(unverified.publicKey.rawRepresentation == verified.publicKey.rawRepresentation)
        #expect(unverified.isVerified != verified.isVerified)
    }
}
