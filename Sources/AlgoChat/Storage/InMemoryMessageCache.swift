import Algorand
import Foundation

/// In-memory implementation of MessageCache
///
/// Useful for testing and ephemeral caching. Data is lost when the app terminates.
public actor InMemoryMessageCache: MessageCache {
    private var messagesByParticipant: [String: [Message]] = [:]
    private var lastSyncRounds: [String: UInt64] = [:]

    public init() {}

    public func store(_ messages: [Message], for participant: Address) async throws {
        let key = participant.description
        var existing = messagesByParticipant[key] ?? []

        // Merge with existing, deduplicating by ID
        let existingIds = Set(existing.map(\.id))
        let newMessages = messages.filter { !existingIds.contains($0.id) }
        existing.append(contentsOf: newMessages)

        // Sort by timestamp
        existing.sort { $0.timestamp < $1.timestamp }
        messagesByParticipant[key] = existing
    }

    public func retrieve(for participant: Address, afterRound: UInt64?) async throws -> [Message] {
        let key = participant.description
        let messages = messagesByParticipant[key] ?? []

        if let afterRound = afterRound {
            return messages.filter { $0.confirmedRound > afterRound }
        }
        return messages
    }

    public func getLastSyncRound(for participant: Address) async throws -> UInt64? {
        lastSyncRounds[participant.description]
    }

    public func setLastSyncRound(_ round: UInt64, for participant: Address) async throws {
        lastSyncRounds[participant.description] = round
    }

    public func getCachedConversations() async throws -> [Address] {
        messagesByParticipant.keys.compactMap { try? Address(string: $0) }
    }

    public func clear() async throws {
        messagesByParticipant.removeAll()
        lastSyncRounds.removeAll()
    }

    public func clear(for participant: Address) async throws {
        let key = participant.description
        messagesByParticipant.removeValue(forKey: key)
        lastSyncRounds.removeValue(forKey: key)
    }
}
