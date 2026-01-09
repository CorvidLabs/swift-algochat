import Algorand
@preconcurrency import Crypto
import Foundation

/**
 Protocol for storing and retrieving encryption keys

 Implementations can store keys in memory, Keychain with biometric protection,
 or other secure storage mechanisms.
 */
public protocol EncryptionKeyStorage: Sendable {
    /**
     Store an encryption private key for an Algorand address

     - Parameters:
       - privateKey: The X25519 private key to store
       - address: The Algorand address this key belongs to
       - requireBiometric: If true, require biometric/passcode to access
     - Throws: `KeyStorageError` if storage fails
     */
    func store(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        for address: Address,
        requireBiometric: Bool
    ) async throws

    /**
     Retrieve an encryption private key for an Algorand address

     This may trigger a biometric prompt if the key was stored with protection.

     - Parameter address: The Algorand address to retrieve the key for
     - Returns: The stored X25519 private key
     - Throws: `KeyStorageError` if retrieval fails or key not found
     */
    func retrieve(for address: Address) async throws -> Curve25519.KeyAgreement.PrivateKey

    /**
     Check if a key exists for an address without retrieving it

     - Parameter address: The Algorand address to check
     - Returns: true if a key is stored for this address
     */
    func hasKey(for address: Address) async -> Bool

    /**
     Delete the stored key for an address

     - Parameter address: The Algorand address to delete the key for
     - Throws: `KeyStorageError` if deletion fails
     */
    func delete(for address: Address) async throws

    /**
     List all addresses that have stored keys

     - Returns: Array of Algorand addresses with stored encryption keys
     */
    func listStoredAddresses() async throws -> [Address]
}

/// Errors that can occur during key storage operations
public enum KeyStorageError: Error, LocalizedError {
    case keyNotFound(Address)
    case storageFailed(String)
    case retrievalFailed(String)
    case biometricNotAvailable
    case biometricFailed
    case invalidKeyData
    case passwordRequired
    case decryptionFailed
    case directoryNotFound

    public var errorDescription: String? {
        switch self {
        case .keyNotFound(let address):
            return "No encryption key found for \(address)"
        case .storageFailed(let reason):
            return "Failed to store key: \(reason)"
        case .retrievalFailed(let reason):
            return "Failed to retrieve key: \(reason)"
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .invalidKeyData:
            return "Stored key data is invalid"
        case .passwordRequired:
            return "Password is required to access stored keys"
        case .decryptionFailed:
            return "Failed to decrypt key - incorrect password"
        case .directoryNotFound:
            return "Could not find application support directory"
        }
    }
}
