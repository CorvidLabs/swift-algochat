#if os(iOS) || os(macOS) || os(visionOS)
@preconcurrency import Foundation
import LocalAuthentication
import Security

/// Secure account storage with biometric protection
///
/// Stores account mnemonics in the system Keychain, protected by Touch ID,
/// Face ID, Optic ID, or device passcode. Account metadata (address, name,
/// network) is stored separately in UserDefaults for listing without
/// triggering biometric prompts.
///
/// ## Usage
///
/// ```swift
/// let storage = AccountStorage()
///
/// // Save an account
/// try await storage.save(mnemonic: words, for: address, network: "testnet", name: "Main")
///
/// // List accounts (no biometric prompt)
/// let accounts = storage.listAccounts()
///
/// // Retrieve mnemonic (triggers biometric)
/// let mnemonic = try await storage.retrieveMnemonic(for: account)
/// ```
public actor AccountStorage {
    /// Service identifier for Keychain items
    private let service = "com.algochat.account-mnemonics"

    /// UserDefaults key for account metadata
    private let metadataKey = "AlgoChatSavedAccounts"

    /// Prompt message shown during biometric authentication
    public var authenticationPrompt = "Authenticate to access your account"

    public init() {}

    // MARK: - Save

    /// Saves an account mnemonic with biometric protection
    ///
    /// - Parameters:
    ///   - mnemonic: The 25-word recovery phrase
    ///   - address: The Algorand address
    ///   - network: Network identifier ("testnet" or "mainnet")
    ///   - name: Optional display name for the account
    public func save(
        mnemonic: String,
        for address: String,
        network: String,
        name: String? = nil
    ) async throws {
        // Delete any existing entry first
        try? await delete(for: address)

        // Store mnemonic in Keychain
        guard let mnemonicData = mnemonic.data(using: .utf8) else {
            throw AccountStorageError.invalidMnemonic
        }

        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.userPresence],
            nil
        ) else {
            throw AccountStorageError.storageFailed("Failed to create access control")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address,
            kSecValueData as String: mnemonicData,
            kSecAttrAccessControl as String: accessControl,
            kSecAttrSynchronizable as String: false,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw AccountStorageError.storageFailed(securityErrorMessage(status))
        }

        // Save metadata to UserDefaults
        var accounts = loadMetadata()
        let account = SavedAccount(
            address: address,
            name: name,
            network: network
        )
        accounts.removeAll { $0.address == address }
        accounts.append(account)
        saveMetadata(accounts)
    }

    // MARK: - Retrieve

    /// Retrieves the mnemonic for an account (triggers biometric prompt)
    ///
    /// - Parameter account: The saved account to retrieve
    /// - Returns: The 25-word mnemonic
    /// - Throws: `AccountStorageError` if retrieval fails
    public func retrieveMnemonic(for account: SavedAccount) async throws -> String {
        try await retrieveMnemonic(for: account.address)
    }

    /// Retrieves the mnemonic for an address (triggers biometric prompt)
    ///
    /// - Parameter address: The Algorand address
    /// - Returns: The 25-word mnemonic
    /// - Throws: `AccountStorageError` if retrieval fails
    public func retrieveMnemonic(for address: String) async throws -> String {
        let context = LAContext()
        context.localizedReason = authenticationPrompt

        let query: CFDictionary = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ] as CFDictionary

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query, &result)

                if status == errSecSuccess, let data = result as? Data,
                   let mnemonic = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: mnemonic)
                } else if status == errSecItemNotFound {
                    continuation.resume(throwing: AccountStorageError.accountNotFound(address))
                } else if status == errSecUserCanceled {
                    continuation.resume(throwing: AccountStorageError.biometricCanceled)
                } else if status == errSecAuthFailed {
                    continuation.resume(throwing: AccountStorageError.biometricFailed)
                } else {
                    continuation.resume(
                        throwing: AccountStorageError.retrievalFailed(
                            self.securityErrorMessage(status)
                        )
                    )
                }
            }
        }
    }

    // MARK: - Delete

    /// Deletes a saved account
    ///
    /// - Parameter account: The account to delete
    public func delete(for account: SavedAccount) async throws {
        try await delete(for: account.address)
    }

    /// Deletes a saved account by address
    ///
    /// - Parameter address: The Algorand address to delete
    public func delete(for address: String) async throws {
        // Delete from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountStorageError.storageFailed(securityErrorMessage(status))
        }

        // Remove from metadata
        var accounts = loadMetadata()
        accounts.removeAll { $0.address == address }
        saveMetadata(accounts)
    }

    // MARK: - List

    /// Lists all saved accounts (does not trigger biometric prompt)
    ///
    /// - Returns: Array of saved accounts sorted by last used date
    public func listAccounts() -> [SavedAccount] {
        loadMetadata().sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Checks if any accounts are saved
    public var hasAccounts: Bool {
        !loadMetadata().isEmpty
    }

    // MARK: - Update

    /// Updates the last used timestamp for an account
    ///
    /// - Parameter address: The Algorand address
    public func updateLastUsed(for address: String) {
        var accounts = loadMetadata()
        if let index = accounts.firstIndex(where: { $0.address == address }) {
            accounts[index].lastUsed = Date()
            saveMetadata(accounts)
        }
    }

    /// Updates the display name for an account
    ///
    /// - Parameters:
    ///   - address: The Algorand address
    ///   - name: The new display name
    public func updateName(for address: String, name: String?) {
        var accounts = loadMetadata()
        if let index = accounts.firstIndex(where: { $0.address == address }) {
            accounts[index].name = name
            saveMetadata(accounts)
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

    /// The type of biometric available (Face ID, Touch ID, Optic ID, or none)
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

    // MARK: - Private Helpers

    private func loadMetadata() -> [SavedAccount] {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let accounts = try? JSONDecoder().decode([SavedAccount].self, from: data) else {
            return []
        }
        return accounts
    }

    private func saveMetadata(_ accounts: [SavedAccount]) {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    private nonisolated func securityErrorMessage(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Unknown error (code: \(status))"
    }
}

// MARK: - Errors

/// Errors that can occur during account storage operations
public enum AccountStorageError: Error, LocalizedError, Sendable {
    case invalidMnemonic
    case accountNotFound(String)
    case storageFailed(String)
    case retrievalFailed(String)
    case biometricCanceled
    case biometricFailed

    public var errorDescription: String? {
        switch self {
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .accountNotFound(let address):
            return "Account not found: \(address)"
        case .storageFailed(let message):
            return "Failed to save account: \(message)"
        case .retrievalFailed(let message):
            return "Failed to retrieve account: \(message)"
        case .biometricCanceled:
            return "Authentication was canceled"
        case .biometricFailed:
            return "Authentication failed"
        }
    }
}

#else

// Fallback for unsupported platforms (tvOS, watchOS, Linux)
import Foundation

/// In-memory account storage for platforms without Keychain support
///
/// Accounts are stored only in memory and will be lost when the app closes.
public actor AccountStorage {
    private var mnemonics: [String: String] = [:]
    private var metadata: [SavedAccount] = []

    public var authenticationPrompt = "Authenticate to access your account"

    public init() {}

    public func save(
        mnemonic: String,
        for address: String,
        network: String,
        name: String? = nil
    ) async throws {
        mnemonics[address] = mnemonic
        metadata.removeAll { $0.address == address }
        metadata.append(SavedAccount(address: address, name: name, network: network))
    }

    public func retrieveMnemonic(for account: SavedAccount) async throws -> String {
        try await retrieveMnemonic(for: account.address)
    }

    public func retrieveMnemonic(for address: String) async throws -> String {
        guard let mnemonic = mnemonics[address] else {
            throw AccountStorageError.accountNotFound(address)
        }
        return mnemonic
    }

    public func delete(for account: SavedAccount) async throws {
        try await delete(for: account.address)
    }

    public func delete(for address: String) async throws {
        mnemonics.removeValue(forKey: address)
        metadata.removeAll { $0.address == address }
    }

    public func listAccounts() -> [SavedAccount] {
        metadata.sorted { $0.lastUsed > $1.lastUsed }
    }

    public var hasAccounts: Bool {
        !metadata.isEmpty
    }

    public func updateLastUsed(for address: String) {
        if let index = metadata.firstIndex(where: { $0.address == address }) {
            metadata[index].lastUsed = Date()
        }
    }

    public func updateName(for address: String, name: String?) {
        if let index = metadata.firstIndex(where: { $0.address == address }) {
            metadata[index].name = name
        }
    }

    public static var isBiometricAvailable: Bool { false }

    public enum BiometricType: String, Sendable {
        case none = "None"
    }

    public static var biometricType: BiometricType { .none }
}

public enum AccountStorageError: Error, LocalizedError, Sendable {
    case invalidMnemonic
    case accountNotFound(String)
    case storageFailed(String)
    case retrievalFailed(String)
    case biometricCanceled
    case biometricFailed

    public var errorDescription: String? {
        switch self {
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .accountNotFound(let address):
            return "Account not found: \(address)"
        case .storageFailed(let message):
            return "Failed to save account: \(message)"
        case .retrievalFailed(let message):
            return "Failed to retrieve account: \(message)"
        case .biometricCanceled:
            return "Authentication was canceled"
        case .biometricFailed:
            return "Authentication failed"
        }
    }
}

#endif
