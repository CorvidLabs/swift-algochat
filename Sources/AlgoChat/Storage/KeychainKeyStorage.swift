#if os(iOS) || os(macOS) || os(visionOS)
import Algorand
@preconcurrency import Crypto
@preconcurrency import Foundation
import LocalAuthentication
import Security

/// Keychain-based encryption key storage with biometric protection
///
/// Stores X25519 encryption keys in the system Keychain, optionally protected
/// by Touch ID, Face ID, or device passcode.
///
/// ## Usage
///
/// ```swift
/// let storage = KeychainKeyStorage()
///
/// // Store a key with biometric protection
/// try await storage.store(privateKey: key, for: address, requireBiometric: true)
///
/// // Retrieve (will prompt for Touch ID/Face ID)
/// let key = try await storage.retrieve(for: address)
/// ```
///
/// ## Security
///
/// - Keys are stored in the Secure Enclave when available
/// - Keys are NOT synced to iCloud
/// - Keys are tied to this device only
/// - Biometric check happens in hardware
public actor KeychainKeyStorage: EncryptionKeyStorage {
    /// Service identifier for Keychain items
    private let service = "com.algochat.encryption-keys"

    /// Prompt message shown during biometric authentication
    public var authenticationPrompt = "Authenticate to access your encrypted messages"

    public init() {}

    // MARK: - EncryptionKeyStorage

    public func store(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        for address: Address,
        requireBiometric: Bool
    ) async throws {
        let account = address.description
        let keyData = privateKey.rawRepresentation

        // Delete any existing key first
        try? await delete(for: address)

        // Build the query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrSynchronizable as String: false,  // Don't sync to iCloud
        ]

        // Add biometric protection if requested
        if requireBiometric {
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.userPresence],  // Requires biometric OR passcode
                nil
            ) else {
                throw KeyStorageError.storageFailed("Failed to create access control")
            }
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        // Store the key
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeyStorageError.storageFailed(securityErrorMessage(status))
        }
    }

    public func retrieve(for address: Address) async throws -> Curve25519.KeyAgreement.PrivateKey {
        let account = address.description

        // Create LAContext for authentication prompt
        let context = LAContext()
        context.localizedReason = authenticationPrompt

        let query: CFDictionary = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ] as CFDictionary

        // Retrieve must run on background thread for biometric prompt
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query, &result)

                if status == errSecSuccess, let data = result as? Data {
                    do {
                        let privateKey = try Curve25519.KeyAgreement.PrivateKey(
                            rawRepresentation: data
                        )
                        continuation.resume(returning: privateKey)
                    } catch {
                        continuation.resume(throwing: KeyStorageError.invalidKeyData)
                    }
                } else if status == errSecItemNotFound {
                    continuation.resume(throwing: KeyStorageError.keyNotFound(address))
                } else if status == errSecUserCanceled {
                    continuation.resume(throwing: KeyStorageError.biometricFailed)
                } else if status == errSecAuthFailed {
                    continuation.resume(throwing: KeyStorageError.biometricFailed)
                } else {
                    continuation.resume(
                        throwing: KeyStorageError.retrievalFailed(
                            self.securityErrorMessage(status)
                        )
                    )
                }
            }
        }
    }

    public func hasKey(for address: Address) async -> Bool {
        let account = address.description

        // Use LAContext with interactionNotAllowed to check without prompting
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed means item exists but needs auth
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public func delete(for address: Address) async throws {
        let account = address.description

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStorageError.storageFailed(securityErrorMessage(status))
        }
    }

    public func listStoredAddresses() async throws -> [Address] {
        // Use LAContext with interactionNotAllowed to list without prompting
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess || status == errSecInteractionNotAllowed,
              let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item -> Address? in
            guard let account = item[kSecAttrAccount as String] as? String else {
                return nil
            }
            return try? Address(string: account)
        }
    }

    // MARK: - Biometric Availability

    /// Check if biometric authentication is available on this device
    public static var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }

    /// The type of biometric available (Face ID, Touch ID, or none)
    public static var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        ) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    /// Types of biometric authentication
    public enum BiometricType: String, Sendable {
        case none = "None"
        case touchID = "Touch ID"
        case faceID = "Face ID"
        case opticID = "Optic ID"
    }

    // MARK: - Private

    private nonisolated func securityErrorMessage(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Unknown error (code: \(status))"
    }
}

#else

// Fallback for unsupported platforms (tvOS, watchOS, Linux)
import Algorand
@preconcurrency import Crypto
import Foundation

/// In-memory key storage for platforms without Keychain support
///
/// Keys are stored only in memory and will be lost when the app closes.
/// This is a fallback for platforms that don't support Keychain with biometrics.
public actor KeychainKeyStorage: EncryptionKeyStorage {
    private var keys: [String: Data] = [:]

    public init() {}

    public func store(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        for address: Address,
        requireBiometric: Bool
    ) async throws {
        // Ignore requireBiometric on unsupported platforms
        keys[address.description] = privateKey.rawRepresentation
    }

    public func retrieve(for address: Address) async throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let data = keys[address.description] else {
            throw KeyStorageError.keyNotFound(address)
        }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    public func hasKey(for address: Address) async -> Bool {
        keys[address.description] != nil
    }

    public func delete(for address: Address) async throws {
        keys.removeValue(forKey: address.description)
    }

    public func listStoredAddresses() async throws -> [Address] {
        keys.keys.compactMap { try? Address(string: $0) }
    }

    public static var isBiometricAvailable: Bool { false }

    public enum BiometricType: String, Sendable {
        case none = "None"
    }

    public static var biometricType: BiometricType { .none }
}

#endif
