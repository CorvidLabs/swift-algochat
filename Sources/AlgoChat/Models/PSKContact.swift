import Foundation

/// Information about a PSK contact for pre-shared key messaging
public struct PSKContact: Sendable, Codable, Equatable {
    /// The contact's Algorand address (description string)
    public let address: String

    /// The 32-byte initial pre-shared key
    public let initialPSK: Data

    /// Optional human-readable label for the contact
    public let label: String?

    /// When the contact was created
    public let createdAt: Date

    /// Creates a new PSK contact
    ///
    /// - Parameters:
    ///   - address: The contact's Algorand address
    ///   - initialPSK: The 32-byte pre-shared key
    ///   - label: Optional human-readable label
    ///   - createdAt: Creation date (defaults to now)
    public init(
        address: String,
        initialPSK: Data,
        label: String? = nil,
        createdAt: Date = Date()
    ) {
        precondition(initialPSK.count == 32, "Initial PSK must be 32 bytes")
        self.address = address
        self.initialPSK = initialPSK
        self.label = label
        self.createdAt = createdAt
    }
}
