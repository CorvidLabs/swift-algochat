import Algorand
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

/// Tests for FileKeyStorage - password-protected file-based key storage
/// Serialized because PBKDF2 with 100K iterations is CPU-intensive and
/// concurrent execution can crash BoringSSL on Linux CI.
@Suite("FileKeyStorage Tests", .serialized)
struct FileKeyStorageTests {
    // MARK: - Test Helpers

    /// Creates a unique test address for isolation
    private func createTestAddress() throws -> Address {
        let account = try Account()
        return account.address
    }

    /// Cleans up a stored key after test
    private func cleanup(address: Address, storage: FileKeyStorage) async {
        try? await storage.delete(for: address)
    }

    // MARK: - Store and Retrieve Tests

    @Test("Store and retrieve encryption key with password")
    func testStoreAndRetrieveWithPassword() async throws {
        let storage = FileKeyStorage(password: "test-password-123")
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        defer { Task { await cleanup(address: address, storage: storage) } }

        // Store the key
        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)

        // Verify it exists
        let hasKey = await storage.hasKey(for: address)
        #expect(hasKey == true)

        // Retrieve it
        let retrieved = try await storage.retrieve(for: address)

        // Verify it matches
        #expect(retrieved.rawRepresentation == privateKey.rawRepresentation)
    }

    @Test("Store and retrieve multiple keys")
    func testStoreMultipleKeys() async throws {
        let storage = FileKeyStorage(password: "multi-key-password")
        let address1 = try createTestAddress()
        let address2 = try createTestAddress()
        let key1 = Curve25519.KeyAgreement.PrivateKey()
        let key2 = Curve25519.KeyAgreement.PrivateKey()

        defer {
            Task {
                await cleanup(address: address1, storage: storage)
                await cleanup(address: address2, storage: storage)
            }
        }

        // Store both keys
        try await storage.store(privateKey: key1, for: address1, requireBiometric: false)
        try await storage.store(privateKey: key2, for: address2, requireBiometric: false)

        // Retrieve and verify
        let retrieved1 = try await storage.retrieve(for: address1)
        let retrieved2 = try await storage.retrieve(for: address2)

        #expect(retrieved1.rawRepresentation == key1.rawRepresentation)
        #expect(retrieved2.rawRepresentation == key2.rawRepresentation)
    }

    @Test("Overwriting key replaces old one")
    func testOverwriteKey() async throws {
        let storage = FileKeyStorage(password: "overwrite-test")
        let address = try createTestAddress()
        let key1 = Curve25519.KeyAgreement.PrivateKey()
        let key2 = Curve25519.KeyAgreement.PrivateKey()

        defer { Task { await cleanup(address: address, storage: storage) } }

        // Store first key
        try await storage.store(privateKey: key1, for: address, requireBiometric: false)

        // Store second key (should replace)
        try await storage.store(privateKey: key2, for: address, requireBiometric: false)

        // Retrieve should return second key
        let retrieved = try await storage.retrieve(for: address)
        #expect(retrieved.rawRepresentation == key2.rawRepresentation)
        #expect(retrieved.rawRepresentation != key1.rawRepresentation)
    }

    // MARK: - Password Requirement Tests

    @Test("Store without password throws passwordRequired")
    func testStoreWithoutPasswordThrows() async throws {
        let storage = FileKeyStorage()  // No password
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        await #expect(throws: KeyStorageError.self) {
            try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)
        }
    }

    @Test("Retrieve without password throws passwordRequired")
    func testRetrieveWithoutPasswordThrows() async throws {
        // First store with password
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let storageWithPassword = FileKeyStorage(password: "store-password")

        defer { Task { await cleanup(address: address, storage: storageWithPassword) } }

        try await storageWithPassword.store(privateKey: privateKey, for: address, requireBiometric: false)

        // Try to retrieve without password
        let storageNoPassword = FileKeyStorage()

        await #expect(throws: KeyStorageError.self) {
            _ = try await storageNoPassword.retrieve(for: address)
        }
    }

    @Test("Store with empty password throws passwordRequired")
    func testStoreWithEmptyPasswordThrows() async throws {
        let storage = FileKeyStorage(password: "")
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        await #expect(throws: KeyStorageError.self) {
            try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)
        }
    }

    // MARK: - Wrong Password Tests

    @Test("Retrieve with wrong password throws decryptionFailed")
    func testWrongPasswordThrows() async throws {
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        // Store with correct password
        let correctStorage = FileKeyStorage(password: "correct-password")
        defer { Task { await cleanup(address: address, storage: correctStorage) } }

        try await correctStorage.store(privateKey: privateKey, for: address, requireBiometric: false)

        // Try to retrieve with wrong password
        let wrongStorage = FileKeyStorage(password: "wrong-password")

        await #expect(throws: KeyStorageError.self) {
            _ = try await wrongStorage.retrieve(for: address)
        }
    }

    // MARK: - setPassword and clearPassword Tests

    @Test("setPassword allows access after initialization without password")
    func testSetPasswordAfterInit() async throws {
        let storage = FileKeyStorage()  // No initial password
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        defer { Task { await cleanup(address: address, storage: storage) } }

        // Set password
        await storage.setPassword("deferred-password")

        // Now store should work
        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)

        // And retrieve should work
        let retrieved = try await storage.retrieve(for: address)
        #expect(retrieved.rawRepresentation == privateKey.rawRepresentation)
    }

    @Test("clearPassword prevents subsequent access")
    func testClearPasswordPreventsAccess() async throws {
        let storage = FileKeyStorage(password: "initial-password")
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        defer { Task { await cleanup(address: address, storage: storage) } }

        // Store with password
        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)

        // Clear password
        await storage.clearPassword()

        // Retrieve should now fail
        await #expect(throws: KeyStorageError.self) {
            _ = try await storage.retrieve(for: address)
        }
    }

    @Test("Changing password clears cache and requires correct password")
    func testChangingPasswordClearsCache() async throws {
        let storage = FileKeyStorage(password: "password-one")
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        defer { Task { await cleanup(address: address, storage: storage) } }

        // Store with first password
        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)

        // Retrieve works
        let retrieved1 = try await storage.retrieve(for: address)
        #expect(retrieved1.rawRepresentation == privateKey.rawRepresentation)

        // Change password (different from what was used to encrypt)
        await storage.setPassword("password-two")

        // Retrieve should fail (wrong password for the encrypted file)
        await #expect(throws: KeyStorageError.self) {
            _ = try await storage.retrieve(for: address)
        }
    }

    // MARK: - Delete Tests

    @Test("Delete removes stored key")
    func testDeleteKey() async throws {
        let storage = FileKeyStorage(password: "delete-test")
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        // Store and verify
        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)
        #expect(await storage.hasKey(for: address) == true)

        // Delete
        try await storage.delete(for: address)

        // Verify it's gone
        #expect(await storage.hasKey(for: address) == false)
    }

    @Test("Delete non-existent key does not throw")
    func testDeleteNonExistentKey() async throws {
        let storage = FileKeyStorage(password: "delete-test")
        let address = try createTestAddress()

        // Should not throw
        try await storage.delete(for: address)
    }

    // MARK: - hasKey Tests

    @Test("hasKey returns false for non-existent key")
    func testHasKeyFalseForNonExistent() async throws {
        let storage = FileKeyStorage(password: "haskey-test")
        let address = try createTestAddress()

        let hasKey = await storage.hasKey(for: address)
        #expect(hasKey == false)
    }

    @Test("hasKey works without password set")
    func testHasKeyWithoutPassword() async throws {
        // First store a key
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let storageWithPassword = FileKeyStorage(password: "store-password")

        defer { Task { await cleanup(address: address, storage: storageWithPassword) } }

        try await storageWithPassword.store(privateKey: privateKey, for: address, requireBiometric: false)

        // Check hasKey without password (should still work - just checks file existence)
        let storageNoPassword = FileKeyStorage()
        let hasKey = await storageNoPassword.hasKey(for: address)
        #expect(hasKey == true)
    }

    // MARK: - listStoredAddresses Tests

    @Test("listStoredAddresses returns stored addresses")
    func testListStoredAddresses() async throws {
        let storage = FileKeyStorage(password: "list-test")
        let address1 = try createTestAddress()
        let address2 = try createTestAddress()
        let key1 = Curve25519.KeyAgreement.PrivateKey()
        let key2 = Curve25519.KeyAgreement.PrivateKey()

        defer {
            Task {
                await cleanup(address: address1, storage: storage)
                await cleanup(address: address2, storage: storage)
            }
        }

        // Store both keys
        try await storage.store(privateKey: key1, for: address1, requireBiometric: false)
        try await storage.store(privateKey: key2, for: address2, requireBiometric: false)

        // List addresses
        let addresses = try await storage.listStoredAddresses()

        #expect(addresses.contains(address1))
        #expect(addresses.contains(address2))
    }

    // MARK: - Retrieve Non-Existent Key Tests

    @Test("Retrieve non-existent key throws keyNotFound")
    func testRetrieveNonExistentKeyThrows() async throws {
        let storage = FileKeyStorage(password: "notfound-test")
        let address = try createTestAddress()

        await #expect(throws: KeyStorageError.self) {
            _ = try await storage.retrieve(for: address)
        }
    }

    // MARK: - File Format Tests

    @Test("Stored file has correct minimum size")
    func testStoredFileSize() async throws {
        let storage = FileKeyStorage(password: "size-test")
        let address = try createTestAddress()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        defer { Task { await cleanup(address: address, storage: storage) } }

        try await storage.store(privateKey: privateKey, for: address, requireBiometric: false)

        // File should exist and have correct size
        // Format: salt (32) + nonce (12) + ciphertext (32) + tag (16) = 92 bytes
        let homeDir: URL
        #if os(Linux)
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            homeDir = URL(fileURLWithPath: home)
        } else {
            homeDir = URL(fileURLWithPath: "/tmp")
        }
        #else
        homeDir = FileManager.default.homeDirectoryForCurrentUser
        #endif

        let keyPath = homeDir
            .appendingPathComponent(".algochat/keys")
            .appendingPathComponent("\(address.description).key")

        let fileData = try Data(contentsOf: keyPath)
        #expect(fileData.count == 92)
    }
}

@Suite("FileKeyStorage Error Description Tests")
struct FileKeyStorageErrorTests {
    @Test("passwordRequired error has meaningful description")
    func testPasswordRequiredDescription() {
        let error = KeyStorageError.passwordRequired
        #expect(error.errorDescription?.contains("Password") == true)
    }

    @Test("decryptionFailed error has meaningful description")
    func testDecryptionFailedDescription() {
        let error = KeyStorageError.decryptionFailed
        #expect(error.errorDescription?.contains("decrypt") == true)
    }
}
