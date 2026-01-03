import Algorand
@preconcurrency import Crypto
import Foundation

/// Protocol for caching discovered public keys
///
/// Reduces blockchain queries when sending messages by caching
/// previously discovered recipient public keys.
///
/// Keys are stored and retrieved as raw bytes (`Data`) to enable
/// Sendable conformance across actor boundaries in Swift 6.
public protocol PublicKeyCacheProtocol: Sendable {
    /// Store a public key for an address
    ///
    /// - Parameters:
    ///   - keyData: The X25519 public key raw representation
    ///   - address: The Algorand address this key belongs to
    func store(_ keyData: Data, for address: Address) async

    /// Retrieve a cached public key's raw representation
    ///
    /// - Parameter address: The Algorand address to look up
    /// - Returns: The cached public key raw bytes, or nil if not found/expired
    func retrieve(for address: Address) async -> Data?

    /// Invalidate a cached public key
    ///
    /// Call this if key discovery fails or the key appears to be invalid.
    ///
    /// - Parameter address: The address to invalidate
    func invalidate(for address: Address) async

    /// Clear all cached keys
    func clear() async
}

/// In-memory implementation of PublicKeyCache
///
/// Stores public keys in memory with optional TTL expiration.
/// Keys are stored as raw bytes (Data) to enable Sendable conformance
/// across actor boundaries in Swift 6.
public actor PublicKeyCache: PublicKeyCacheProtocol {
    private struct CachedKeyData: Sendable {
        let rawRepresentation: Data
        let cachedAt: Date
    }

    private var cache: [String: CachedKeyData] = [:]

    /// Time-to-live for cached keys (default: 24 hours)
    public let ttl: TimeInterval

    /// Create a new public key cache
    ///
    /// - Parameter ttl: Time-to-live for cached entries (default: 24 hours)
    public init(ttl: TimeInterval = 86400) {
        self.ttl = ttl
    }

    public func store(_ keyData: Data, for address: Address) async {
        cache[address.description] = CachedKeyData(
            rawRepresentation: keyData,
            cachedAt: Date()
        )
    }

    public func retrieve(for address: Address) async -> Data? {
        guard let cached = cache[address.description] else {
            return nil
        }

        // Check if expired
        if Date().timeIntervalSince(cached.cachedAt) > ttl {
            cache.removeValue(forKey: address.description)
            return nil
        }

        return cached.rawRepresentation
    }

    public func invalidate(for address: Address) async {
        cache.removeValue(forKey: address.description)
    }

    public func clear() async {
        cache.removeAll()
    }

    /// Remove all expired entries
    public func pruneExpired() async {
        let now = Date()
        cache = cache.filter { _, value in
            now.timeIntervalSince(value.cachedAt) <= ttl
        }
    }
}
