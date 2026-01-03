import Algorand
@preconcurrency import Crypto
import Foundation

/// Verifies that encryption public keys are genuinely owned by Algorand accounts
///
/// This prevents key substitution attacks by requiring that encryption keys
/// be signed with the Algorand account's Ed25519 key. The signature proves
/// that the encryption key was published by the holder of the private key
/// for that Algorand address.
///
/// ## Security Model
///
/// ```
/// Publish: Account.Ed25519.sign(X25519_PublicKey) → signature
/// Verify:  Address.Ed25519.verify(signature, X25519_PublicKey) → valid?
/// ```
///
/// ## Usage
///
/// ```swift
/// // Sign when publishing
/// let signature = try SignatureVerifier.sign(
///     encryptionPublicKey: chatAccount.publicKeyData,
///     with: chatAccount.account
/// )
///
/// // Verify when discovering
/// let isValid = try SignatureVerifier.verify(
///     encryptionPublicKey: discoveredKey,
///     signedBy: senderAddress,
///     signature: envelopeSignature
/// )
/// ```
public enum SignatureVerifier {
    /// Size of an Ed25519 signature (64 bytes)
    public static let signatureSize = 64

    // MARK: - Signing

    /// Signs an encryption public key with an Algorand account's Ed25519 key
    ///
    /// This creates a cryptographic proof that the encryption key belongs to
    /// the holder of the Algorand account's private key.
    ///
    /// - Parameters:
    ///   - encryptionPublicKey: The X25519 public key to sign (32 bytes)
    ///   - account: The Algorand account to sign with
    /// - Returns: The Ed25519 signature (64 bytes)
    /// - Throws: `ChatError` if signing fails
    public static func sign(
        encryptionPublicKey: Data,
        with account: Account
    ) throws -> Data {
        guard encryptionPublicKey.count == 32 else {
            throw ChatError.invalidPublicKey(
                "Encryption public key must be 32 bytes, got \(encryptionPublicKey.count)"
            )
        }

        do {
            let signature = try account.sign(encryptionPublicKey)
            return signature
        } catch {
            throw ChatError.keyDerivationFailed("Failed to sign encryption key: \(error)")
        }
    }

    // MARK: - Verification

    /// Verifies that an encryption public key was signed by an Algorand account
    ///
    /// This checks that the signature over the X25519 encryption key was
    /// created by the Ed25519 private key corresponding to the given address.
    ///
    /// - Parameters:
    ///   - encryptionPublicKey: The X25519 public key (32 bytes)
    ///   - address: The Algorand address that supposedly signed the key
    ///   - signature: The Ed25519 signature to verify (64 bytes)
    /// - Returns: `true` if the signature is valid
    /// - Throws: `ChatError` if verification cannot be performed
    public static func verify(
        encryptionPublicKey: Data,
        signedBy address: Address,
        signature: Data
    ) throws -> Bool {
        guard encryptionPublicKey.count == 32 else {
            throw ChatError.invalidPublicKey(
                "Encryption public key must be 32 bytes, got \(encryptionPublicKey.count)"
            )
        }

        guard signature.count == signatureSize else {
            throw ChatError.invalidSignature(
                "Signature must be \(signatureSize) bytes, got \(signature.count)"
            )
        }

        // The address bytes ARE the Ed25519 public key
        let ed25519PublicKeyData = address.bytes

        guard ed25519PublicKeyData.count == 32 else {
            throw ChatError.invalidPublicKey(
                "Address public key must be 32 bytes, got \(ed25519PublicKeyData.count)"
            )
        }

        // Create Ed25519 public key for verification
        guard let publicKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: ed25519PublicKeyData
        ) else {
            throw ChatError.invalidPublicKey("Failed to create Ed25519 public key from address")
        }

        // Verify the signature over the encryption public key
        return publicKey.isValidSignature(signature, for: encryptionPublicKey)
    }

    // MARK: - Key Fingerprint

    /// Generates a human-readable fingerprint for an encryption public key
    ///
    /// The fingerprint is a truncated SHA-256 hash formatted for easy comparison.
    ///
    /// - Parameter publicKey: The encryption public key (32 bytes)
    /// - Returns: A fingerprint string like "A7B3 C9D1 E5F2 8A4B"
    public static func fingerprint(of publicKey: Data) -> String {
        let hash = SHA256.hash(data: publicKey)
        let bytes = Array(hash.prefix(8))
        return bytes
            .map { String(format: "%02X", $0) }
            .chunked(into: 2)
            .map { $0.joined() }
            .joined(separator: " ")
    }
}

// MARK: - Array Extension

private extension Array {
    /// Splits array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
