import Algorand
@preconcurrency import Crypto
import Foundation

#if canImport(Security)
import Security
#endif

#if canImport(CommonCrypto)
import CommonCrypto
#endif

/**
 File-based encryption key storage with password protection

 Stores X25519 encryption keys encrypted with AES-256-GCM, using a password
 derived key via PBKDF2. Keys are stored in `~/.algochat/keys/`.

 This is the primary storage mechanism for Linux and can be used on any platform.

 ## Storage Format

 Each key file contains:
 - Salt: 32 bytes (random, for PBKDF2)
 - Nonce: 12 bytes (random, for AES-GCM)
 - Ciphertext: 32 bytes + 16 byte tag (encrypted private key)

 ## Security

 - Uses PBKDF2 with 100,000 iterations for key derivation
 - Uses AES-256-GCM for authenticated encryption
 - Keys are stored with 600 permissions (owner read/write only)
 - Salt is unique per key file

 ## Usage

 ```swift
 let storage = FileKeyStorage(password: "user-password")

 // Store a key
 try await storage.store(privateKey: key, for: address, requireBiometric: false)

 // Retrieve
 let key = try await storage.retrieve(for: address)
 ```
 */
public actor FileKeyStorage: EncryptionKeyStorage {
    // MARK: - Constants

    /// PBKDF2 iteration count (OWASP recommendation for SHA256)
    private static let pbkdf2Iterations = 100_000

    /// Salt size in bytes
    private static let saltSize = 32

    /// AES-GCM nonce size in bytes
    private static let nonceSize = 12

    /// Directory name for key storage
    private static let directoryName = ".algochat/keys"

    // MARK: - Properties

    /// The password used for encryption/decryption
    private var password: String?

    /// Cached derived key (cleared when password changes)
    private var cachedDerivedKey: SymmetricKey?

    /// Salt used for the cached key
    private var cachedSalt: Data?

    // MARK: - Initialization

    /**
     Creates a new file key storage

     - Parameter password: Optional password for encryption. If nil, password must
       be set before storing or retrieving keys.
     */
    public init(password: String? = nil) {
        self.password = password
    }

    /// Sets the password for encryption/decryption
    ///
    /// - Parameter password: The password to use
    public func setPassword(_ password: String) {
        self.password = password
        self.cachedDerivedKey = nil
        self.cachedSalt = nil
    }

    /// Clears the password and cached keys from memory
    public func clearPassword() {
        self.password = nil
        self.cachedDerivedKey = nil
        self.cachedSalt = nil
    }

    // MARK: - EncryptionKeyStorage

    public func store(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        for address: Address,
        requireBiometric: Bool
    ) async throws {
        guard let password = password, !password.isEmpty else {
            throw KeyStorageError.passwordRequired
        }

        // Ensure directory exists
        let directory = try keyStorageDirectory()

        // Generate random salt and nonce
        let salt = try generateRandomBytes(count: Self.saltSize)
        let nonce = try generateRandomBytes(count: Self.nonceSize)

        // Derive encryption key from password
        let derivedKey = try deriveKey(from: password, salt: salt)

        // Encrypt the private key
        let plaintext = privateKey.rawRepresentation
        let gcmNonce = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.seal(plaintext, using: derivedKey, nonce: gcmNonce)

        // Combine: salt + nonce + ciphertext (includes tag)
        var fileData = Data()
        fileData.append(salt)
        fileData.append(nonce)
        fileData.append(sealedBox.ciphertext)
        fileData.append(sealedBox.tag)

        // Write to file
        let filePath = keyFilePath(for: address, in: directory)
        try fileData.write(to: filePath)

        // Set restrictive permissions (owner read/write only)
        try setRestrictivePermissions(for: filePath)
    }

    public func retrieve(for address: Address) async throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let password = password, !password.isEmpty else {
            throw KeyStorageError.passwordRequired
        }

        let directory = try keyStorageDirectory()
        let filePath = keyFilePath(for: address, in: directory)

        // Read the encrypted file
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw KeyStorageError.keyNotFound(address)
        }

        let fileData = try Data(contentsOf: filePath)

        // Parse: salt (32) + nonce (12) + ciphertext (32) + tag (16) = 92 bytes minimum
        guard fileData.count >= Self.saltSize + Self.nonceSize + 32 + 16 else {
            throw KeyStorageError.invalidKeyData
        }

        let salt = fileData.prefix(Self.saltSize)
        let nonce = fileData.dropFirst(Self.saltSize).prefix(Self.nonceSize)
        let ciphertextAndTag = fileData.dropFirst(Self.saltSize + Self.nonceSize)

        // Derive decryption key from password
        let derivedKey = try deriveKey(from: password, salt: salt)

        // Decrypt
        let gcmNonce = try AES.GCM.Nonce(data: nonce)
        let tagSize = 16
        let ciphertext = ciphertextAndTag.dropLast(tagSize)
        let tag = ciphertextAndTag.suffix(tagSize)

        let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: ciphertext, tag: tag)

        do {
            let plaintext = try AES.GCM.open(sealedBox, using: derivedKey)
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: plaintext)
        } catch {
            throw KeyStorageError.decryptionFailed
        }
    }

    public func hasKey(for address: Address) async -> Bool {
        guard let directory = try? keyStorageDirectory() else {
            return false
        }
        let filePath = keyFilePath(for: address, in: directory)
        return FileManager.default.fileExists(atPath: filePath.path)
    }

    public func delete(for address: Address) async throws {
        let directory = try keyStorageDirectory()
        let filePath = keyFilePath(for: address, in: directory)

        if FileManager.default.fileExists(atPath: filePath.path) {
            try FileManager.default.removeItem(at: filePath)
        }
    }

    public func listStoredAddresses() async throws -> [Address] {
        let directory = try keyStorageDirectory()

        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        // Files are named with address hash, we need to read metadata
        // For now, return addresses from filenames (first 58 chars)
        return files.compactMap { file -> Address? in
            let name = file.deletingPathExtension().lastPathComponent
            return try? Address(string: name)
        }
    }

    // MARK: - Private Methods

    /// Gets or creates the key storage directory
    private func keyStorageDirectory() throws -> URL {
        try StorageDirectory.resolve(name: Self.directoryName)
    }

    /// Returns the file path for a key
    private func keyFilePath(for address: Address, in directory: URL) -> URL {
        // Use full address as filename (it's already unique)
        directory.appendingPathComponent("\(address.description).key")
    }

    /// Derives an encryption key from password using PBKDF2
    private func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        // Check cache
        if let cached = cachedDerivedKey, cachedSalt == salt {
            return cached
        }

        guard let passwordData = password.data(using: .utf8) else {
            throw KeyStorageError.storageFailed("Invalid password encoding")
        }

        // PBKDF2 with SHA256
        let derivedKey = try PBKDF2<SHA256>.deriveKey(
            from: passwordData,
            salt: salt,
            iterations: Self.pbkdf2Iterations,
            keyByteCount: 32
        )

        // Cache for this salt
        cachedDerivedKey = derivedKey
        cachedSalt = salt

        return derivedKey
    }

    /// Generates cryptographically secure random bytes
    ///
    /// Uses the platform CSPRNG (`SecRandomCopyBytes` on Apple platforms,
    /// `/dev/urandom` on Linux) rather than a non-cryptographic generator.
    ///
    /// - Parameter count: The number of random bytes to generate
    /// - Returns: The generated random bytes
    /// - Throws: `KeyStorageError.storageFailed` if secure randomness is unavailable
    private func generateRandomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw KeyStorageError.storageFailed("Failed to generate secure random bytes")
        }
        #else
        // Linux: use /dev/urandom which is cryptographically secure
        guard let urandom = FileHandle(forReadingAtPath: "/dev/urandom") else {
            throw KeyStorageError.storageFailed("Failed to open /dev/urandom")
        }
        defer { try? urandom.close() }
        let randomData = urandom.readData(ofLength: count)
        guard randomData.count == count else {
            throw KeyStorageError.storageFailed("Failed to read enough random bytes from /dev/urandom")
        }
        bytes = [UInt8](randomData)
        #endif
        return Data(bytes)
    }

    /// Sets restrictive file permissions (600 on Unix)
    private func setRestrictivePermissions(for url: URL) throws {
        #if os(Linux) || os(macOS)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        #endif
    }
}

// MARK: - PBKDF2 Implementation

/**
 PBKDF2-HMAC-SHA256 key derivation (RFC 8018)

 This is a real PBKDF2 implementation so that derived keys are
 interoperable with the reference implementations (rs/py) and match the
 crypto spec: PBKDF2-HMAC-SHA256 with 100,000 iterations, producing a
 32-byte AES-256 key.

 On Apple platforms `CCKeyDerivationPBKDF` from CommonCrypto is used.
 On other platforms (e.g. Linux) a vetted RFC 8018 implementation built on
 swift-crypto's `HMAC<SHA256>` is used.

 - Note: Only SHA-256 is supported; the generic `Hash` parameter exists to
   preserve the call site, but a non-SHA-256 hash is rejected at runtime.
 */
internal enum PBKDF2<Hash: HashFunction> {
    /**
     Derives a symmetric key from a password using PBKDF2-HMAC-SHA256

     - Parameters:
       - password: The password data
       - salt: The salt data
       - iterations: Number of PBKDF2 iterations
       - keyByteCount: Desired output key length in bytes
     - Returns: The derived symmetric key
     - Throws: `KeyStorageError.storageFailed` if derivation fails
     */
    internal static func deriveKey(
        from password: Data,
        salt: Data,
        iterations: Int,
        keyByteCount: Int
    ) throws -> SymmetricKey {
        guard Hash.self == SHA256.self else {
            throw KeyStorageError.storageFailed("PBKDF2 only supports SHA-256")
        }

        let derived = try pbkdf2HMACSHA256(
            password: password,
            salt: salt,
            iterations: iterations,
            keyByteCount: keyByteCount
        )

        return SymmetricKey(data: derived)
    }

    /// Performs PBKDF2-HMAC-SHA256, dispatching to CommonCrypto when available.
    private static func pbkdf2HMACSHA256(
        password: Data,
        salt: Data,
        iterations: Int,
        keyByteCount: Int
    ) throws -> Data {
        #if canImport(CommonCrypto)
        var derived = [UInt8](repeating: 0, count: keyByteCount)
        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            password.withUnsafeBytes { passwordBytes -> Int32 in
                salt.withUnsafeBytes { saltBytes -> Int32 in
                    guard
                        let derivedBase = derivedBytes.baseAddress,
                        let saltBase = saltBytes.baseAddress
                    else {
                        return Int32(kCCParamError)
                    }
                    let passwordBase = passwordBytes.baseAddress?
                        .assumingMemoryBound(to: CChar.self)
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBase,
                        passwordBytes.count,
                        saltBase.assumingMemoryBound(to: UInt8.self),
                        saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBase.assumingMemoryBound(to: UInt8.self),
                        keyByteCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw KeyStorageError.storageFailed("PBKDF2 derivation failed (status \(status))")
        }

        return Data(derived)
        #else
        return try pbkdf2HMACSHA256Pure(
            password: password,
            salt: salt,
            iterations: iterations,
            keyByteCount: keyByteCount
        )
        #endif
    }

    /**
     Pure-Swift PBKDF2-HMAC-SHA256 per RFC 8018, built on swift-crypto HMAC.

     Used on platforms without CommonCrypto (e.g. Linux). Produces identical
     output to CommonCrypto and the reference implementations.
     */
    private static func pbkdf2HMACSHA256Pure(
        password: Data,
        salt: Data,
        iterations: Int,
        keyByteCount: Int
    ) throws -> Data {
        guard iterations > 0, keyByteCount > 0 else {
            throw KeyStorageError.storageFailed("Invalid PBKDF2 parameters")
        }

        let key = SymmetricKey(data: password)
        let hLen = SHA256.byteCount
        let blockCount = Int((Double(keyByteCount) / Double(hLen)).rounded(.up))

        var output = Data()
        output.reserveCapacity(blockCount * hLen)

        for block in 1...blockCount {
            // INT(block): 4-byte big-endian block index
            var blockIndex = UInt32(block).bigEndian
            var saltBlock = salt
            withUnsafeBytes(of: &blockIndex) { saltBlock.append(contentsOf: $0) }

            // U_1 = HMAC(password, salt || INT(block))
            var u = Data(HMAC<SHA256>.authenticationCode(for: saltBlock, using: key))
            var result = u

            // U_2 .. U_c, XOR-accumulated into result
            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for index in 0..<hLen {
                        result[index] ^= u[index]
                    }
                }
            }

            output.append(result)
        }

        return output.prefix(keyByteCount)
    }
}
