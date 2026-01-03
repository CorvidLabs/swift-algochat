import Foundation

/// A saved account that can be restored with biometric authentication
public struct SavedAccount: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let address: String
    public var name: String?
    public let network: String
    public let dateAdded: Date
    public var lastUsed: Date

    public init(
        id: UUID = UUID(),
        address: String,
        name: String? = nil,
        network: String,
        dateAdded: Date = Date(),
        lastUsed: Date = Date()
    ) {
        self.id = id
        self.address = address
        self.name = name
        self.network = network
        self.dateAdded = dateAdded
        self.lastUsed = lastUsed
    }

    // MARK: - Display Helpers

    public var displayName: String {
        name ?? truncatedAddress
    }

    public var truncatedAddress: String {
        if address.count > 12 {
            return "\(address.prefix(6))...\(address.suffix(4))"
        }
        return address
    }
}
