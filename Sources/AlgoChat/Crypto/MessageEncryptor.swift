@preconcurrency import Crypto
import Foundation

#if canImport(Security)
import Security
#endif

/**
 Encrypts and decrypts chat messages using ChaCha20-Poly1305

 Uses ephemeral key ECDH with bidirectional decryption:
 - Generates fresh key pair per message for forward secrecy
 - Encrypts symmetric key for sender, allowing sender to decrypt sent messages
 - Both sender and recipient can decrypt the message
 */
public enum MessageEncryptor {
    // MARK: - Components

    /// Ephemeral key manager for encryption
    private static let ephemeralKeyManager = EphemeralKeyManager()

    // MARK: - Encryption

    /**
     Encrypts a message for a recipient using ephemeral key agreement

     Uses ephemeral key agreement: a fresh key pair is generated for each message,
     providing sender-side forward secrecy. The envelope also includes an encrypted
     copy of the symmetric key for the sender, enabling bidirectional decryption.

     - Parameters:
       - message: The plaintext message
       - senderPrivateKey: Sender's static X25519 private key
       - recipientPublicKey: Recipient's X25519 public key
     - Returns: ChatEnvelope containing encrypted data
     */
    public static func encrypt(
        message: String,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        guard let messageData = message.data(using: .utf8) else {
            throw ChatError.encodingFailed("Failed to encode message as UTF-8")
        }
        return try encryptData(
            messageData,
            senderPrivateKey: senderPrivateKey,
            recipientPublicKey: recipientPublicKey
        )
    }

    /**
     Encrypts a reply message for a recipient with forward secrecy

     Includes reply metadata in the encrypted payload. The content will
     be formatted with a quoted preview of the original message.

     - Parameters:
       - message: The reply text
       - replyTo: Tuple of original transaction ID and preview text
       - senderPrivateKey: Sender's X25519 private key
       - recipientPublicKey: Recipient's X25519 public key
     - Returns: ChatEnvelope containing encrypted data
     */
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

    /**
     Encrypts raw data for a recipient with forward secrecy

     Used internally and for special payloads like key-publish.

     - Parameters:
       - data: The raw data to encrypt
       - senderPrivateKey: Sender's X25519 private key
       - recipientPublicKey: Recipient's X25519 public key
     - Returns: ChatEnvelope containing encrypted data
     */
    public static func encryptRaw(
        _ data: Data,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        try encryptData(data, senderPrivateKey: senderPrivateKey, recipientPublicKey: recipientPublicKey)
    }

    // MARK: - Internal Encryption

    /// Internal method to encrypt raw data with bidirectional decryption support
    private static func encryptData(
        _ data: Data,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> ChatEnvelope {
        guard data.count <= ChatEnvelope.maxPayloadSize else {
            throw ChatError.messageTooLarge(maxSize: ChatEnvelope.maxPayloadSize)
        }

        // Generate ephemeral key pair for this message
        let ephemeralPrivateKey = ephemeralKeyManager.generateKeyPair()

        // Derive symmetric key for recipient using ephemeral ECDH
        let symmetricKey = try ephemeralKeyManager.deriveEncryptionKey(
            ephemeralPrivateKey: ephemeralPrivateKey,
            recipientPublicKey: recipientPublicKey,
            senderStaticPublicKey: senderPrivateKey.publicKey
        )

        // Generate random nonce (12 bytes for ChaCha20-Poly1305)
        let nonceBytes = try generateRandomBytes(count: 12)
        let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))

        // Encrypt message with ChaCha20-Poly1305
        let sealedBox = try ChaChaPoly.seal(
            data,
            using: symmetricKey,
            nonce: nonce
        )
        let ciphertextWithTag = sealedBox.ciphertext + sealedBox.tag

        // Encrypt the symmetric key for the sender (bidirectional decryption)
        // Derive a sender key using: ephemeral_private * sender_public
        let senderSharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(
            with: senderPrivateKey.publicKey
        )

        // Derive symmetric key for encrypting the main symmetric key
        var senderKeyInfo = Data("AlgoChatV1-SenderKey".utf8)
        senderKeyInfo.append(senderPrivateKey.publicKey.rawRepresentation)
        let senderEncryptionKey = senderSharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPrivateKey.publicKey.rawRepresentation,
            sharedInfo: senderKeyInfo,
            outputByteCount: 32
        )

        // Encrypt the raw symmetric key bytes for the sender (reuse same nonce, different key is safe)
        let symmetricKeyData = symmetricKey.withUnsafeBytes { Data($0) }
        let senderSealedBox = try ChaChaPoly.seal(
            symmetricKeyData,
            using: senderEncryptionKey,
            nonce: nonce
        )
        let encryptedSenderKey = senderSealedBox.ciphertext + senderSealedBox.tag

        return ChatEnvelope(
            senderPublicKey: senderPrivateKey.publicKey.rawRepresentation,
            ephemeralPublicKey: ephemeralPrivateKey.publicKey.rawRepresentation,
            encryptedSenderKey: encryptedSenderKey,
            nonce: Data(nonceBytes),
            ciphertext: ciphertextWithTag
        )
    }

    // MARK: - Decryption

    /**
     Decrypts a message envelope and returns structured content

     Automatically detects whether the caller is the sender or recipient
     and uses the appropriate decryption path. Returns nil for key-publish payloads.

     - Parameters:
       - envelope: The encrypted envelope
       - recipientPrivateKey: The decryptor's X25519 private key (sender or recipient)
     - Returns: DecryptedContent with text and optional reply metadata, or nil for key-publish
     */
    public static func decrypt(
        envelope: ChatEnvelope,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> DecryptedContent? {
        // Reconstruct keys
        let senderStaticPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: envelope.senderPublicKey
        )
        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: envelope.ephemeralPublicKey
        )

        // Check if we're the sender (our public key matches the envelope's sender public key)
        let weAreTheSender = recipientPrivateKey.publicKey.rawRepresentation == envelope.senderPublicKey

        let plaintext: Data
        if weAreTheSender {
            // Sender decryption: use the encrypted sender key
            plaintext = try decryptData(
                envelope: envelope,
                senderPrivateKey: recipientPrivateKey,
                ephemeralPublicKey: ephemeralPublicKey
            )
        } else {
            // Recipient decryption: use ephemeral ECDH
            let symmetricKey = try ephemeralKeyManager.deriveDecryptionKey(
                recipientPrivateKey: recipientPrivateKey,
                ephemeralPublicKey: ephemeralPublicKey,
                senderStaticPublicKey: senderStaticPublicKey
            )
            plaintext = try decryptWithKey(envelope: envelope, symmetricKey: symmetricKey)
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

    // MARK: - Internal Sender Decryption

    /// Internal method to decrypt envelope to raw data
    private static func decryptData(
        envelope: ChatEnvelope,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        ephemeralPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> Data {
        // Derive the sender decryption key: sender_private * ephemeral_public
        let senderSharedSecret = try senderPrivateKey.sharedSecretFromKeyAgreement(
            with: ephemeralPublicKey
        )

        // Derive the key used to encrypt the symmetric key
        var senderKeyInfo = Data("AlgoChatV1-SenderKey".utf8)
        senderKeyInfo.append(senderPrivateKey.publicKey.rawRepresentation)
        let senderDecryptionKey = senderSharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPublicKey.rawRepresentation,
            sharedInfo: senderKeyInfo,
            outputByteCount: 32
        )

        // Decrypt the symmetric key
        let keyNonce = try ChaChaPoly.Nonce(data: envelope.nonce)
        let keyCiphertextLength = envelope.encryptedSenderKey.count - ChatEnvelope.tagSize
        guard keyCiphertextLength == 32 else {
            throw ChatError.decryptionFailed("Invalid encrypted sender key length")
        }
        let keyCiphertext = envelope.encryptedSenderKey.prefix(keyCiphertextLength)
        let keyTag = envelope.encryptedSenderKey.suffix(ChatEnvelope.tagSize)

        let keySealedBox = try ChaChaPoly.SealedBox(
            nonce: keyNonce,
            ciphertext: keyCiphertext,
            tag: keyTag
        )
        let symmetricKeyData = try ChaChaPoly.open(keySealedBox, using: senderDecryptionKey)

        // Use the recovered symmetric key to decrypt the message
        let symmetricKey = SymmetricKey(data: symmetricKeyData)
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

    // MARK: - Helpers

    /// Generates cryptographically secure random bytes
    private static func generateRandomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw ChatError.randomGenerationFailed
        }
        #else
        // Linux: use /dev/urandom which is cryptographically secure
        guard let urandom = FileHandle(forReadingAtPath: "/dev/urandom") else {
            throw ChatError.randomGenerationFailed
        }
        defer { try? urandom.close() }
        let randomData = urandom.readData(ofLength: count)
        guard randomData.count == count else {
            throw ChatError.randomGenerationFailed
        }
        bytes = [UInt8](randomData)
        #endif
        return bytes
    }
}
