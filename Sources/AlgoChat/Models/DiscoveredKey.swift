@preconcurrency import Crypto
import Foundation

/// Result of discovering a user's encryption public key
///
/// Contains the key itself along with metadata about how it was verified.
public struct DiscoveredKey: Sendable {
    /// The X25519 public key for encryption
    public let publicKey: Curve25519.KeyAgreement.PublicKey

    /// Whether this key was cryptographically verified
    ///
    /// A verified key was signed by the account's Ed25519 key (V3 envelope),
    /// proving the key was published by the account owner.
    ///
    /// An unverified key came from a V1/V2 envelope without signature,
    /// which should be verified out-of-band for sensitive communications.
    public let isVerified: Bool

    /// Creates a discovered key result
    ///
    /// - Parameters:
    ///   - publicKey: The X25519 public key
    ///   - isVerified: Whether the key was cryptographically verified
    public init(publicKey: Curve25519.KeyAgreement.PublicKey, isVerified: Bool) {
        self.publicKey = publicKey
        self.isVerified = isVerified
    }
}
