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
        try encryptData(
            message.data(using: .utf8)!,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPublicKey
        )
    }

    /// Encrypts a reply message for a recipient
    ///
    /// Includes reply metadata in the encrypted payload. The content will
    /// be formatted with a quoted preview of the original message.
    ///
    /// - Parameters:
    ///   - message: The reply text
    ///   - replyTo: Tuple of original transaction ID and preview text
    ///   - senderPrivateKey: Sender's X25519 private key
    ///   - recipientPublicKey: Recipient's X25519 public key
    /// - Returns: ChatEnvelope containing encrypted data
    public static func encrypt(
        message: String,
        replyTo: (txid: String, preview: String),
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        let payload = MessagePayload.reply(
            text: message,
            originalTxid: replyTo.txid,
            originalPreview: replyTo.preview
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payloadData = try encoder.encode(payload)

        return try encryptData(
            payloadData,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPublicKey
        )
    }

    /// Encrypts raw data for a recipient
    ///
    /// Used internally and for special payloads like key-publish.
    ///
    /// - Parameters:
    ///   - data: The raw data to encrypt
    ///   - senderPrivateKey: Sender's X25519 private key
    ///   - recipientPublicKey: Recipient's X25519 public key
    /// - Returns: ChatEnvelope containing encrypted data
    public static func encryptRaw(
        _ data: Data,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        try encryptData(data, senderPrivateKey: senderPrivateKey, recipientPublicKey: recipientPublicKey)
    }

    /// Internal method to encrypt raw data
    private static func encryptData(
        _ data: Data,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        guard data.count <= ChatEnvelope.maxPayloadSize else {
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
            data,
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

    /// Decrypts a message envelope and returns structured content
    ///
    /// Returns nil for key-publish payloads, which are used to publish
    /// encryption keys without sending an actual message.
    ///
    /// - Parameters:
    ///   - envelope: The encrypted envelope
    ///   - recipientPrivateKey: Recipient's X25519 private key
    /// - Returns: DecryptedContent with text and optional reply metadata, or nil for key-publish
    public static func decrypt(
        envelope: ChatEnvelope,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> DecryptedContent? {
        let plaintext = try decryptData(
            envelope: envelope,
            recipientPrivateKey: recipientPrivateKey
        )

        // Check for key-publish payload (should be filtered from message list)
        if KeyPublishPayload.isKeyPublish(plaintext) {
            return nil
        }

        // Try to parse as structured payload (JSON with "text" field)
        // If it starts with { and parses successfully, use structured format
        // Otherwise treat as plain text for backward compatibility
        if plaintext.first == UInt8(ascii: "{"),
           let payload = try? JSONDecoder().decode(MessagePayload.self, from: plaintext) {
            return DecryptedContent(
                text: payload.text,
                replyToId: payload.replyTo?.txid,
                replyToPreview: payload.replyTo?.preview
            )
        }

        // Plain text message (v1 format or simple message)
        guard let message = String(data: plaintext, encoding: .utf8) else {
            throw ChatError.decryptionFailed("Decrypted data is not valid UTF-8")
        }

        return DecryptedContent(text: message)
    }

    /// Internal method to decrypt envelope to raw data
    private static func decryptData(
        envelope: ChatEnvelope,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
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

        return try ChaChaPoly.open(sealedBox, using: symmetricKey)
    }
}
