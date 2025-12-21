import Algorand
import Crypto
import Foundation

/// Handles derivation of encryption keys from Algorand signing keys
public enum KeyDerivation {
    /// Salt for HKDF key derivation (domain separation)
    private static let salt = Data("AlgoChat-v1-encryption".utf8)

    /// Info parameter for HKDF
    private static let info = Data("x25519-key".utf8)

    /// Derives X25519 encryption key pair from an Algorand account
    ///
    /// The conversion from Ed25519 to X25519 uses HKDF with domain separation
    /// to derive an independent encryption key from the account's private key material.
    ///
    /// - Parameter account: The Algorand account
    /// - Returns: Tuple of (private key, public key) for Curve25519 key agreement
    public static func deriveEncryptionKeys(
        from account: Account
    ) throws -> (Curve25519.KeyAgreement.PrivateKey, Curve25519.KeyAgreement.PublicKey) {
        let seed = try extractPrivateSeed(from: account)
        let encryptionSeed = deriveEncryptionSeed(from: seed)
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: encryptionSeed)
        return (privateKey, privateKey.publicKey)
    }

    /// Extracts the 32-byte private seed from an Algorand account via mnemonic
    private static func extractPrivateSeed(from account: Account) throws -> Data {
        let mnemonic = try account.mnemonic()
        return try Mnemonic.decode(mnemonic)
    }

    /// Derives encryption seed using HKDF with domain separation
    private static func deriveEncryptionSeed(from signingKey: Data) -> Data {
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: signingKey),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }

    /// Converts an X25519 public key to storable/transmittable format
    public static func encodePublicKey(
        _ publicKey: Curve25519.KeyAgreement.PublicKey
    ) -> Data {
        publicKey.rawRepresentation
    }

    /// Reconstructs an X25519 public key from raw bytes
    public static func decodePublicKey(
        from data: Data
    ) throws -> Curve25519.KeyAgreement.PublicKey {
        guard data.count == 32 else {
            throw ChatError.invalidPublicKey("Public key must be 32 bytes, got \(data.count)")
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }
}
