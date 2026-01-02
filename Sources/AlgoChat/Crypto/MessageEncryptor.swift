@preconcurrency import Crypto
import Foundation

#if canImport(Security)
import Security
#endif

/// Encrypts and decrypts chat messages using ChaCha20-Poly1305
///
/// Supports two encryption modes:
/// - **V1 (Legacy)**: Static key ECDH - uses sender's static key for key agreement
/// - **V2 (Forward Secrecy)**: Ephemeral key ECDH - generates fresh key per message
///
/// V2 provides forward secrecy: compromising a long-term key does not reveal
/// past message contents since each message uses a unique ephemeral key.
public enum MessageEncryptor {
    // MARK: - V1 Constants (Legacy)

    /// Salt for V1 HKDF key derivation
    private static let hkdfSaltV1 = Data("AlgoChat-v1-salt".utf8)

    /// Shared info for V1 HKDF key derivation
    private static let sharedInfoV1 = Data("AlgoChat-v1-message".utf8)

    // MARK: - V2 Components

    /// Ephemeral key manager for V2 encryption
    private static let ephemeralKeyManager = EphemeralKeyManager()

    // MARK: - Encryption (V2 - Forward Secrecy)

    /// Encrypts a message for a recipient with forward secrecy
    ///
    /// Uses ephemeral key agreement: a fresh key pair is generated for each message,
    /// providing forward secrecy. Even if long-term keys are compromised, past
    /// messages remain secure.
    ///
    /// - Parameters:
    ///   - message: The plaintext message
    ///   - senderPrivateKey: Sender's static X25519 private key
    ///   - recipientPublicKey: Recipient's X25519 public key
    /// - Returns: ChatEnvelope containing encrypted data with V2 format
    public static func encrypt(
        message: String,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        guard let messageData = message.data(using: .utf8) else {
            throw ChatError.encodingFailed("Failed to encode message as UTF-8")
        }
        return try encryptDataV2(
            messageData,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPublicKey
        )
    }

    /// Encrypts a reply message for a recipient with forward secrecy
    ///
    /// Includes reply metadata in the encrypted payload. The content will
    /// be formatted with a quoted preview of the original message.
    ///
    /// - Parameters:
    ///   - message: The reply text
    ///   - replyTo: Tuple of original transaction ID and preview text
    ///   - senderPrivateKey: Sender's X25519 private key
    ///   - recipientPublicKey: Recipient's X25519 public key
    /// - Returns: ChatEnvelope containing encrypted data with V2 format
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

        return try encryptDataV2(
            payloadData,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPublicKey
        )
    }

    /// Encrypts raw data for a recipient with forward secrecy
    ///
    /// Used internally and for special payloads like key-publish.
    ///
    /// - Parameters:
    ///   - data: The raw data to encrypt
    ///   - senderPrivateKey: Sender's X25519 private key
    ///   - recipientPublicKey: Recipient's X25519 public key
    /// - Returns: ChatEnvelope containing encrypted data with V2 format
    public static func encryptRaw(
        _ data: Data,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        try encryptDataV2(data, senderPrivateKey: senderPrivateKey, recipientPublicKey: recipientPublicKey)
    }

    // MARK: - V2 Encryption (Forward Secrecy)

    /// Internal method to encrypt raw data with V2 format (ephemeral keys)
    private static func encryptDataV2(
        _ data: Data,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        guard data.count <= ChatEnvelope.maxPayloadSizeV2 else {
            throw ChatError.messageTooLarge(maxSize: ChatEnvelope.maxPayloadSizeV2)
        }

        // Generate ephemeral key pair for this message
        let ephemeralPrivateKey = ephemeralKeyManager.generateKeyPair()

        // Derive symmetric key using ephemeral ECDH
        let symmetricKey = try ephemeralKeyManager.deriveEncryptionKey(
            ephemeralPrivateKey: ephemeralPrivateKey,
            recipientPublicKey: recipientPublicKey,
            senderStaticPublicKey: senderPrivateKey.publicKey
        )

        // Generate random nonce (12 bytes for ChaCha20-Poly1305)
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, 12, &nonceBytes)
        guard status == errSecSuccess else {
            throw ChatError.randomGenerationFailed
        }
        #else
        // Linux: use /dev/urandom which is cryptographically secure
        guard let urandom = FileHandle(forReadingAtPath: "/dev/urandom") else {
            throw ChatError.randomGenerationFailed
        }
        let randomData = urandom.readData(ofLength: 12)
        try? urandom.close()
        guard randomData.count == 12 else {
            throw ChatError.randomGenerationFailed
        }
        nonceBytes = [UInt8](randomData)
        #endif
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
            ephemeralPublicKey: ephemeralPrivateKey.publicKey.rawRepresentation,
            nonce: Data(nonceBytes),
            ciphertext: ciphertextWithTag
        )
    }

    // MARK: - Decryption (Supports V1 and V2)

    /// Decrypts a message envelope and returns structured content
    ///
    /// Automatically detects and handles both V1 (legacy) and V2 (forward secrecy)
    /// envelopes. Returns nil for key-publish payloads.
    ///
    /// - Parameters:
    ///   - envelope: The encrypted envelope
    ///   - recipientPrivateKey: Recipient's X25519 private key
    /// - Returns: DecryptedContent with text and optional reply metadata, or nil for key-publish
    public static func decrypt(
        envelope: ChatEnvelope,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> DecryptedContent? {
        let plaintext: Data

        // Route to appropriate decryption based on envelope version
        if envelope.usesForwardSecrecy {
            plaintext = try decryptDataV2(
                envelope: envelope,
                recipientPrivateKey: recipientPrivateKey
            )
        } else {
            plaintext = try decryptDataV1(
                envelope: envelope,
                recipientPrivateKey: recipientPrivateKey
            )
        }

        // Check for key-publish payload (should be filtered from message list)
        if KeyPublishPayload.isKeyPublish(plaintext) {
            return nil
        }

        // Try to parse as structured payload (JSON with "text" field)
        if plaintext.first == UInt8(ascii: "{"),
           let payload = try? JSONDecoder().decode(MessagePayload.self, from: plaintext) {
            return DecryptedContent(
                text: payload.text,
                replyToId: payload.replyTo?.txid,
                replyToPreview: payload.replyTo?.preview
            )
        }

        // Plain text message (legacy format)
        guard let message = String(data: plaintext, encoding: .utf8) else {
            throw ChatError.decryptionFailed("Decrypted data is not valid UTF-8")
        }

        return DecryptedContent(text: message)
    }

    // MARK: - V1 Decryption (Legacy)

    /// Decrypts a V1 envelope using static key ECDH
    private static func decryptDataV1(
        envelope: ChatEnvelope,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        // Reconstruct sender's public key
        let senderPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: envelope.senderPublicKey
        )

        // Derive shared secret using static keys
        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(
            with: senderPublicKey
        )

        // Derive symmetric key
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: hkdfSaltV1,
            sharedInfo: sharedInfoV1,
            outputByteCount: 32
        )

        return try decryptWithKey(envelope: envelope, symmetricKey: symmetricKey)
    }

    // MARK: - V2 Decryption (Forward Secrecy)

    /// Decrypts a V2 envelope using ephemeral key ECDH
    private static func decryptDataV2(
        envelope: ChatEnvelope,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        guard let ephemeralKeyData = envelope.ephemeralPublicKey else {
            throw ChatError.decryptionFailed("V2 envelope missing ephemeral key")
        }

        // Reconstruct keys
        let senderStaticPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: envelope.senderPublicKey
        )
        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: ephemeralKeyData
        )

        // Derive symmetric key using ephemeral ECDH
        let symmetricKey = try ephemeralKeyManager.deriveDecryptionKey(
            recipientPrivateKey: recipientPrivateKey,
            ephemeralPublicKey: ephemeralPublicKey,
            senderStaticPublicKey: senderStaticPublicKey
        )

        return try decryptWithKey(envelope: envelope, symmetricKey: symmetricKey)
    }

    // MARK: - Common Decryption

    /// Decrypts envelope ciphertext using the provided symmetric key
    private static func decryptWithKey(
        envelope: ChatEnvelope,
        symmetricKey: SymmetricKey
    ) throws -> Data {
        // Extract ciphertext and tag
        let ciphertextLength = envelope.ciphertext.count - ChatEnvelope.tagSize
        guard ciphertextLength >= 0 else {
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
