@preconcurrency import Crypto
import Foundation

/// Manages ephemeral key generation for per-message key isolation
///
/// Each message uses a fresh ephemeral key pair. The symmetric encryption key
/// is derived from the ephemeral private key and recipient's static public key.
/// This provides sender-side forward secrecy: compromising the sender's key
/// does not reveal past messages. Note: recipient key compromise exposes all
/// messages encrypted to that recipient.
public struct EphemeralKeyManager: Sendable {
    public init() {}

    /// Generates a fresh ephemeral key pair for a single message
    ///
    /// - Returns: A new X25519 key pair (private key is used for ECDH, public key is sent in envelope)
    public func generateKeyPair() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    /// Derives a symmetric key for encryption using ephemeral ECDH
    ///
    /// Uses the sender's ephemeral private key and recipient's static public key
    /// to derive a shared secret, then applies HKDF to produce a symmetric key.
    ///
    /// - Parameters:
    ///   - ephemeralPrivateKey: Sender's ephemeral private key (generated per-message)
    ///   - recipientPublicKey: Recipient's static X25519 public key
    ///   - senderStaticPublicKey: Sender's static public key (used in key derivation for binding)
    /// - Returns: A 256-bit symmetric key for ChaCha20-Poly1305
    /// - Throws: `ChatError.keyDerivationFailed` if ECDH fails
    public func deriveEncryptionKey(
        ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey,
        senderStaticPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        // Perform ECDH with ephemeral key
        let sharedSecret: SharedSecret
        do {
            sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        } catch {
            throw ChatError.keyDerivationFailed("Ephemeral ECDH failed: \(error.localizedDescription)")
        }

        // Include sender's static public key in the info to bind the key derivation
        // to both parties' identities
        var info = Data("AlgoChatV2".utf8)
        info.append(senderStaticPublicKey.rawRepresentation)
        info.append(recipientPublicKey.rawRepresentation)

        // Use HKDF to derive the symmetric key
        // Salt is the ephemeral public key for domain separation
        let salt = ephemeralPrivateKey.publicKey.rawRepresentation

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )

        return symmetricKey
    }

    /// Derives a symmetric key for decryption using the recipient's static key
    ///
    /// The recipient uses their static private key with the sender's ephemeral
    /// public key (from the envelope) to derive the same shared secret.
    ///
    /// - Parameters:
    ///   - recipientPrivateKey: Recipient's static private key
    ///   - ephemeralPublicKey: Sender's ephemeral public key (from envelope)
    ///   - senderStaticPublicKey: Sender's static public key (from envelope)
    /// - Returns: A 256-bit symmetric key for ChaCha20-Poly1305
    /// - Throws: `ChatError.keyDerivationFailed` if ECDH fails
    public func deriveDecryptionKey(
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        ephemeralPublicKey: Curve25519.KeyAgreement.PublicKey,
        senderStaticPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        // Perform ECDH with sender's ephemeral key
        let sharedSecret: SharedSecret
        do {
            sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        } catch {
            throw ChatError.keyDerivationFailed("Ephemeral ECDH decryption failed: \(error.localizedDescription)")
        }

        // Must use the same derivation parameters as encryption
        var info = Data("AlgoChatV2".utf8)
        info.append(senderStaticPublicKey.rawRepresentation)
        info.append(recipientPrivateKey.publicKey.rawRepresentation)

        // Salt is the ephemeral public key
        let salt = ephemeralPublicKey.rawRepresentation

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )

        return symmetricKey
    }
}
