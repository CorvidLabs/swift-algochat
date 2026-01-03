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
