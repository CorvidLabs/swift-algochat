import Algorand
import Crypto
import Foundation

/// Protocol for caching discovered public keys
///
/// Reduces blockchain queries when sending messages by caching
/// previously discovered recipient public keys.
public protocol PublicKeyCacheProtocol: Sendable {
    /// Store a public key for an address
    ///
    /// - Parameters:
    ///   - key: The X25519 public key
    ///   - address: The Algorand address this key belongs to
    func store(_ key: Curve25519.KeyAgreement.PublicKey, for address: Address) async

    /// Retrieve a cached public key
    ///
    /// - Parameter address: The Algorand address to look up
    /// - Returns: The cached public key, or nil if not found
    func retrieve(for address: Address) async -> Curve25519.KeyAgreement.PublicKey?

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
public actor PublicKeyCache: PublicKeyCacheProtocol {
    private struct CachedKey {
        let key: Curve25519.KeyAgreement.PublicKey
        let cachedAt: Date
    }

    private var cache: [String: CachedKey] = [:]

    /// Time-to-live for cached keys (default: 24 hours)
    public let ttl: TimeInterval

    /// Create a new public key cache
    ///
    /// - Parameter ttl: Time-to-live for cached entries (default: 24 hours)
    public init(ttl: TimeInterval = 86400) {
        self.ttl = ttl
    }

    public func store(_ key: Curve25519.KeyAgreement.PublicKey, for address: Address) async {
        cache[address.description] = CachedKey(key: key, cachedAt: Date())
    }

    public func retrieve(for address: Address) async -> Curve25519.KeyAgreement.PublicKey? {
        guard let cached = cache[address.description] else {
            return nil
        }

        // Check if expired
        if Date().timeIntervalSince(cached.cachedAt) > ttl {
            cache.removeValue(forKey: address.description)
            return nil
        }

        return cached.key
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
