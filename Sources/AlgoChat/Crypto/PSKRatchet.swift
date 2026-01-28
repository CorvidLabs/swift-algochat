@preconcurrency import Crypto
import Foundation

/// Pure stateless crypto functions for PSK ratcheting key derivation
///
/// Implements the two-level ratchet: initial PSK -> session PSK -> position PSK
/// and the hybrid key derivation combining ECDH shared secrets with PSK material.
public enum PSKRatchet {
    // MARK: - Session/Position Derivation

    /// Derives a session PSK from the initial PSK and a session index
    ///
    /// Uses HKDF with the initial PSK as input key material.
    ///
    /// - Parameters:
    ///   - initialPSK: The 32-byte initial pre-shared key
    ///   - sessionIndex: The session index (counter / 100)
    /// - Returns: A 32-byte derived session PSK
    public static func deriveSessionPSK(initialPSK: Data, sessionIndex: UInt32) -> Data {
        var info = sessionIndex.bigEndian
        let infoData = Data(bytes: &info, count: 4)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: initialPSK),
            salt: Data("AlgoChat-PSK-Session".utf8),
            info: infoData,
            outputByteCount: 32
        )

        return derivedKey.withUnsafeBytes { Data($0) }
    }

    /// Derives a position PSK from a session PSK and a position within the session
    ///
    /// Uses HKDF with the session PSK as input key material.
    ///
    /// - Parameters:
    ///   - sessionPSK: The 32-byte session PSK
    ///   - position: The position within the session (counter % 100)
    /// - Returns: A 32-byte derived position PSK
    public static func derivePositionPSK(sessionPSK: Data, position: UInt32) -> Data {
        var info = position.bigEndian
        let infoData = Data(bytes: &info, count: 4)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sessionPSK),
            salt: Data("AlgoChat-PSK-Position".utf8),
            info: infoData,
            outputByteCount: 32
        )

        return derivedKey.withUnsafeBytes { Data($0) }
    }

    /// Derives the current PSK for a given counter value
    ///
    /// Combines session and position derivation:
    /// - session_index = counter / 100
    /// - position = counter % 100
    ///
    /// - Parameters:
    ///   - initialPSK: The 32-byte initial pre-shared key
    ///   - counter: The ratchet counter value
    /// - Returns: A 32-byte derived PSK for this counter position
    public static func derivePSKAtCounter(initialPSK: Data, counter: UInt32) -> Data {
        let sessionIndex = counter / PSKState.sessionSize
        let position = counter % PSKState.sessionSize

        let sessionPSK = deriveSessionPSK(initialPSK: initialPSK, sessionIndex: sessionIndex)
        return derivePositionPSK(sessionPSK: sessionPSK, position: position)
    }

    // MARK: - Hybrid Key Derivation

    /// Derives a hybrid symmetric key combining ECDH shared secret with PSK material
    ///
    /// Used for encrypting message content to the recipient.
    ///
    /// - Parameters:
    ///   - sharedSecret: The ECDH shared secret (ephemeral_private * recipient_public)
    ///   - currentPSK: The derived PSK for the current counter
    ///   - ephemeralPublicKey: The ephemeral public key (used as salt)
    ///   - senderPublicKey: The sender's static X25519 public key
    ///   - recipientPublicKey: The recipient's static X25519 public key
    /// - Returns: A 256-bit symmetric key for ChaCha20-Poly1305
    public static func deriveHybridSymmetricKey(
        sharedSecret: SharedSecret,
        currentPSK: Data,
        ephemeralPublicKey: Data,
        senderPublicKey: Data,
        recipientPublicKey: Data
    ) -> SymmetricKey {
        // IKM = sharedSecret bytes + currentPSK
        let sharedSecretData = sharedSecret.withUnsafeBytes { Data($0) }
        var ikm = sharedSecretData
        ikm.append(currentPSK)

        // info = "AlgoChatV1-PSK" + senderPubKey + recipientPubKey
        var info = Data("AlgoChatV1-PSK".utf8)
        info.append(senderPublicKey)
        info.append(recipientPublicKey)

        // salt = ephemeralPublicKey
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: ephemeralPublicKey,
            info: info,
            outputByteCount: 32
        )
    }

    /// Derives the sender key for bidirectional decryption in PSK mode
    ///
    /// Used for encrypting the symmetric key so the sender can decrypt their own messages.
    ///
    /// - Parameters:
    ///   - senderSharedSecret: The ECDH shared secret (ephemeral_private * sender_public)
    ///   - currentPSK: The derived PSK for the current counter
    ///   - ephemeralPublicKey: The ephemeral public key (used as salt)
    ///   - senderPublicKey: The sender's static X25519 public key
    /// - Returns: A 256-bit symmetric key for encrypting the main symmetric key
    public static func deriveSenderKey(
        senderSharedSecret: SharedSecret,
        currentPSK: Data,
        ephemeralPublicKey: Data,
        senderPublicKey: Data
    ) -> SymmetricKey {
        // IKM = senderSharedSecret bytes + currentPSK
        let sharedSecretData = senderSharedSecret.withUnsafeBytes { Data($0) }
        var ikm = sharedSecretData
        ikm.append(currentPSK)

        // info = "AlgoChatV1-PSK-SenderKey" + senderPubKey
        var info = Data("AlgoChatV1-PSK-SenderKey".utf8)
        info.append(senderPublicKey)

        // salt = ephemeralPublicKey
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: ephemeralPublicKey,
            info: info,
            outputByteCount: 32
        )
    }
}
