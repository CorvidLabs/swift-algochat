import Algorand
@preconcurrency import Crypto
import Foundation

/**
 A chat-enabled Algorand account with encryption keys

 Note: Uses `@unchecked Sendable` because `Curve25519` keys from swift-crypto
 are not marked `Sendable` but are effectively immutable and thread-safe.
 */
public struct ChatAccount: @unchecked Sendable {
    /// The underlying Algorand account
    public let account: Account

    /// The X25519 private key for encryption (derived from Ed25519)
    internal let encryptionPrivateKey: Curve25519.KeyAgreement.PrivateKey

    /// The X25519 public key for encryption
    public let encryptionPublicKey: Curve25519.KeyAgreement.PublicKey

    /// The Algorand address
    public var address: Address { account.address }

    // MARK: - Standard Initializers

    /// Creates a new random chat account
    public init() throws {
        let account = try Account()
        self.account = account
        (self.encryptionPrivateKey, self.encryptionPublicKey) =
            try KeyDerivation.deriveEncryptionKeys(from: account)
    }

    /// Creates a chat account from a mnemonic
    public init(mnemonic: String) throws {
        let account = try Account(mnemonic: mnemonic)
        self.account = account
        (self.encryptionPrivateKey, self.encryptionPublicKey) =
            try KeyDerivation.deriveEncryptionKeys(from: account)
    }

    /// Creates a chat account from an existing Algorand account
    public init(account: Account) throws {
        self.account = account
        (self.encryptionPrivateKey, self.encryptionPublicKey) =
            try KeyDerivation.deriveEncryptionKeys(from: account)
    }

    // MARK: - Keychain-Based Initialization

    /**
     Creates a chat account using a stored encryption key from Keychain

     This allows loading the encryption key via biometric authentication
     without needing to provide the full mnemonic.

     - Parameters:
       - account: The Algorand account (for signing transactions)
       - storage: The key storage to retrieve the encryption key from
     - Throws: `KeyStorageError` if the key is not found or biometric fails
     */
    public init(
        account: Account,
        storage: EncryptionKeyStorage
    ) async throws {
        self.account = account
        self.encryptionPrivateKey = try await storage.retrieve(for: account.address)
        self.encryptionPublicKey = encryptionPrivateKey.publicKey
    }

    /**
     Creates a chat account with only an encryption key (no signing capability)

     This is useful for read-only access to messages when you have the
     encryption key stored but don't have the full account mnemonic.

     - Parameters:
       - address: The Algorand address
       - encryptionKey: The X25519 private key for decryption
     - Note: This account cannot sign transactions (send messages)
     */
    internal init(
        address: Address,
        encryptionKey: Curve25519.KeyAgreement.PrivateKey
    ) throws {
        // Create a dummy account - this won't be usable for signing
        // but allows us to read/decrypt messages
        self.account = try Account()  // Placeholder - address won't match
        self.encryptionPrivateKey = encryptionKey
        self.encryptionPublicKey = encryptionKey.publicKey
    }

    // MARK: - Keychain Operations

    /**
     Saves the encryption key to Keychain with biometric protection

     After calling this, the account can be loaded in future sessions
     using biometric authentication instead of the mnemonic.

     - Parameters:
       - storage: The key storage to save to
       - requireBiometric: If true, require biometric/passcode to access
     */
    public func saveEncryptionKey(
        to storage: EncryptionKeyStorage,
        requireBiometric: Bool = true
    ) async throws {
        try await storage.store(
            privateKey: encryptionPrivateKey,
            for: address,
            requireBiometric: requireBiometric
        )
    }

    /**
     Checks if an encryption key is stored for this account

     - Parameter storage: The key storage to check
     - Returns: true if a key exists in storage for this address
     */
    public func hasStoredEncryptionKey(
        in storage: EncryptionKeyStorage
    ) async -> Bool {
        await storage.hasKey(for: address)
    }

    /**
     Deletes the stored encryption key for this account

     - Parameter storage: The key storage to delete from
     */
    public func deleteStoredEncryptionKey(
        from storage: EncryptionKeyStorage
    ) async throws {
        try await storage.delete(for: address)
    }

    // MARK: - Public Key Data

    /// The encryption public key as raw bytes (for sharing with others)
    public var publicKeyData: Data {
        encryptionPublicKey.rawRepresentation
    }
}

extension ChatAccount: CustomStringConvertible {
    public var description: String {
        "ChatAccount(\(address))"
    }
}
