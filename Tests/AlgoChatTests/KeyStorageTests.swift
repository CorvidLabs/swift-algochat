import Algorand
import Crypto
import Foundation
import Testing
@testable import AlgoChat

/// Tests for encryption key storage
@Suite("Key Storage Tests")
struct KeyStorageTests {

    // MARK: - In-Memory Storage Tests (for testing without biometric)

    /// A simple in-memory implementation for testing
    actor MockKeyStorage: EncryptionKeyStorage {
        private var keys: [String: Data] = [:]

        func store(
            privateKey: Curve25519.KeyAgreement.PrivateKey,
            for address: Address,
            requireBiometric: Bool
        ) async throws {
            keys[address.description] = privateKey.rawRepresentation
        }

        func retrieve(for address: Address) async throws -> Curve25519.KeyAgreement.PrivateKey {
            guard let data = keys[address.description] else {
                throw KeyStorageError.keyNotFound(address)
            }
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }

        func hasKey(for address: Address) async -> Bool {
            keys[address.description] != nil
        }

        func delete(for address: Address) async throws {
            keys.removeValue(forKey: address.description)
        }

        func listStoredAddresses() async throws -> [Address] {
            keys.keys.compactMap { try? Address(string: $0) }
        }
    }

    @Test("Store and retrieve encryption key")
    func testStoreAndRetrieve() async throws {
        let storage = MockKeyStorage()
        let account = try Account()
        let address = account.address

        // Create an encryption key
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        // Store it
        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)

        // Verify it exists
        let hasKey = await storage.hasKey(for: address)
        #expect(hasKey == true)

        // Retrieve it
        let retrieved = try await storage.retrieve(for: address)

        // Verify it matches
        #expect(retrieved.rawRepresentation == privateKey.rawRepresentation)
    }

    @Test("Delete stored key")
    func testDeleteKey() async throws {
        let storage = MockKeyStorage()
        let account = try Account()
        let address = account.address
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        // Store and verify
        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)
        #expect(await storage.hasKey(for: address) == true)

        // Delete
        try await storage.delete(for: address)

        // Verify it's gone
        #expect(await storage.hasKey(for: address) == false)
    }

    @Test("Retrieve non-existent key throws error")
    func testRetrieveNonExistentKey() async throws {
        let storage = MockKeyStorage()
        let account = try Account()

        await #expect(throws: KeyStorageError.self) {
            _ = try await storage.retrieve(for: account.address)
        }
    }

    @Test("List stored addresses")
    func testListAddresses() async throws {
        let storage = MockKeyStorage()

        // Store keys for multiple accounts
        let account1 = try Account()
        let account2 = try Account()
        let key1 = Curve25519.KeyAgreement.PrivateKey()
        let key2 = Curve25519.KeyAgreement.PrivateKey()

        try await storage.store(privateKey: key1, for: account1.address, requireBiometric: false)
        try await storage.store(privateKey: key2, for: account2.address, requireBiometric: false)

        // List addresses
        let addresses = try await storage.listStoredAddresses()

        #expect(addresses.count == 2)
        #expect(addresses.contains(account1.address))
        #expect(addresses.contains(account2.address))
    }

    @Test("ChatAccount saves and loads from storage")
    func testChatAccountWithStorage() async throws {
        let storage = MockKeyStorage()

        // Create a chat account
        let originalAccount = try ChatAccount()

        // Save the encryption key
        try await originalAccount.saveEncryptionKey(to: storage, requireBiometric: false)

        // Verify it's stored
        #expect(await originalAccount.hasStoredEncryptionKey(in: storage) == true)

        // Load using the same Algorand account
        let loadedAccount = try await ChatAccount(
            account: originalAccount.account,
            storage: storage
        )

        // Verify the encryption keys match
        #expect(
            loadedAccount.encryptionPublicKey.rawRepresentation ==
            originalAccount.encryptionPublicKey.rawRepresentation
        )
    }

    @Test("Overwriting key replaces old one")
    func testOverwriteKey() async throws {
        let storage = MockKeyStorage()
        let account = try Account()
        let address = account.address

        let key1 = Curve25519.KeyAgreement.PrivateKey()
        let key2 = Curve25519.KeyAgreement.PrivateKey()

        // Store first key
        try await storage.store(privateKey: key1, for: address, requireBiometric: false)

        // Store second key (should replace)
        try await storage.store(privateKey: key2, for: address, requireBiometric: false)

        // Retrieve should return second key
        let retrieved = try await storage.retrieve(for: address)
        #expect(retrieved.rawRepresentation == key2.rawRepresentation)
    }
}

@Suite("KeyStorageError Tests")
struct KeyStorageErrorTests {
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() throws {
        let address = try Address(string: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAY5HFKQ")

        let keyNotFound = KeyStorageError.keyNotFound(address)
        #expect(keyNotFound.errorDescription?.contains("No encryption key found") == true)

        let storageFailed = KeyStorageError.storageFailed("test reason")
        #expect(storageFailed.errorDescription?.contains("test reason") == true)

        let retrievalFailed = KeyStorageError.retrievalFailed("test reason")
        #expect(retrievalFailed.errorDescription?.contains("test reason") == true)

        let biometricNotAvailable = KeyStorageError.biometricNotAvailable
        #expect(biometricNotAvailable.errorDescription?.contains("not available") == true)

        let biometricFailed = KeyStorageError.biometricFailed
        #expect(biometricFailed.errorDescription?.contains("failed") == true)

        let invalidKeyData = KeyStorageError.invalidKeyData
        #expect(invalidKeyData.errorDescription?.contains("invalid") == true)
    }
}
