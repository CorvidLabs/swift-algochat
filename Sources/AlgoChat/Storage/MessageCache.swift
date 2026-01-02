import Algorand
import Foundation

/// Protocol for caching messages locally
///
/// Implementations can store messages in memory, SQLite, or other storage mechanisms.
/// The cache enables offline access and reduces blockchain queries.
public protocol MessageCache: Sendable {
    /// Store messages for a conversation
    ///
    /// - Parameters:
    ///   - messages: The messages to store
    ///   - participant: The conversation participant address
    /// - Throws: If storage fails
    func store(_ messages: [Message], for participant: Address) async throws

    /// Retrieve cached messages for a conversation
    ///
    /// - Parameters:
    ///   - participant: The conversation participant address
    ///   - afterRound: Only return messages after this round (optional)
    /// - Returns: Array of cached messages, sorted by timestamp
    func retrieve(for participant: Address, afterRound: UInt64?) async throws -> [Message]

    /// Get the last synced blockchain round for a conversation
    ///
    /// - Parameter participant: The conversation participant address
    /// - Returns: The last round that was synced, or nil if never synced
    func getLastSyncRound(for participant: Address) async throws -> UInt64?

    /// Set the last synced blockchain round for a conversation
    ///
    /// - Parameters:
    ///   - round: The round number
    ///   - participant: The conversation participant address
    func setLastSyncRound(_ round: UInt64, for participant: Address) async throws

    /// Get all cached conversations
    ///
    /// - Returns: Array of participant addresses with cached messages
    func getCachedConversations() async throws -> [Address]

    /// Clear all cached data
    func clear() async throws

    /// Clear cache for a specific conversation
    ///
    /// - Parameter participant: The conversation participant address
    func clear(for participant: Address) async throws
}

/// Errors that can occur during message cache operations
public enum MessageCacheError: Error, LocalizedError {
    case storageFailed(String)
    case retrievalFailed(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .storageFailed(let reason):
            return "Failed to store messages: \(reason)"
        case .retrievalFailed(let reason):
            return "Failed to retrieve messages: \(reason)"
        case .notFound:
            return "No cached messages found"
        }
    }
}
