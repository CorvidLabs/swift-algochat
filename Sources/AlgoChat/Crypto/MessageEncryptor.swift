import Crypto
import Foundation

/// Encrypts and decrypts chat messages using ChaCha20-Poly1305
public enum MessageEncryptor {
    /// Shared info for HKDF key derivation
    private static let sharedInfo = Data("AlgoChat-v1-message".utf8)

    /// Encrypts a message for a recipient
    ///
    /// Uses X25519 key agreement to derive a shared secret, then encrypts
    /// the message with ChaCha20-Poly1305.
    ///
    /// - Parameters:
    ///   - message: The plaintext message
    ///   - senderPrivateKey: Sender's X25519 private key
    ///   - recipientPublicKey: Recipient's X25519 public key
    /// - Returns: ChatEnvelope containing encrypted data
    public static func encrypt(
        message: String,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        guard let messageData = message.data(using: .utf8) else {
            throw ChatError.decryptionFailed("Message is not valid UTF-8")
        }

        guard messageData.count <= ChatEnvelope.maxPayloadSize else {
            throw ChatError.messageTooLarge(maxSize: ChatEnvelope.maxPayloadSize)
        }

        // Derive shared secret using X25519 key agreement
        let sharedSecret = try senderPrivateKey.sharedSecretFromKeyAgreement(
            with: recipientPublicKey
        )

        // Derive symmetric key using HKDF
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )

        // Generate random nonce (12 bytes for ChaCha20-Poly1305)
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<12 {
            nonceBytes[i] = UInt8.random(in: 0...255)
        }
        let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))

        // Encrypt with ChaCha20-Poly1305
        let sealedBox = try ChaChaPoly.seal(
            messageData,
            using: symmetricKey,
            nonce: nonce
        )

        // Combine ciphertext and tag
        let ciphertextWithTag = sealedBox.ciphertext + sealedBox.tag

        return ChatEnvelope(
            senderPublicKey: senderPrivateKey.publicKey.rawRepresentation,
            nonce: Data(nonceBytes),
            ciphertext: ciphertextWithTag
        )
    }

    /// Decrypts a message envelope
    ///
    /// - Parameters:
    ///   - envelope: The encrypted envelope
    ///   - recipientPrivateKey: Recipient's X25519 private key
    /// - Returns: Decrypted plaintext message
    public static func decrypt(
        envelope: ChatEnvelope,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> String {
        // Reconstruct sender's public key
        let senderPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: envelope.senderPublicKey
        )

        // Derive shared secret
        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(
            with: senderPublicKey
        )

        // Derive symmetric key
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )

        // Extract ciphertext and tag
        let ciphertextLength = envelope.ciphertext.count - ChatEnvelope.tagSize
        guard ciphertextLength > 0 else {
            throw ChatError.decryptionFailed("Ciphertext too short")
        }

        let ciphertext = envelope.ciphertext.prefix(ciphertextLength)
        let tag = envelope.ciphertext.suffix(ChatEnvelope.tagSize)

        // Reconstruct sealed box and decrypt
        let nonce = try ChaChaPoly.Nonce(data: envelope.nonce)
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        let plaintext = try ChaChaPoly.open(sealedBox, using: symmetricKey)

        guard let message = String(data: plaintext, encoding: .utf8) else {
            throw ChatError.decryptionFailed("Decrypted data is not valid UTF-8")
        }

        return message
    }
}
