import Foundation

/// Manages PSK contacts and ratchet state with in-memory caching backed by persistent storage
public actor PSKManager {
    // MARK: - Properties

    /// Persistent storage backend
    private let storage: any PSKStorage

    /// In-memory contact cache
    private var contactCache: [String: PSKContact] = [:]

    /// In-memory state cache
    private var stateCache: [String: PSKState] = [:]

    // MARK: - Initialization

    /**
     Creates a new PSK manager with the given storage backend

     - Parameter storage: The PSK storage implementation
     */
    public init(storage: any PSKStorage) {
        self.storage = storage
    }

    // MARK: - Contact Management

    /**
     Adds a PSK contact

     - Parameter contact: The PSK contact to add
     */
    public func addContact(_ contact: PSKContact) async throws {
        try await storage.storeContact(contact)
        contactCache[contact.address] = contact
        // Initialize state if not already present
        if stateCache[contact.address] == nil {
            let state = PSKState()
            try await storage.storeState(state, for: contact.address)
            stateCache[contact.address] = state
        }
    }

    /**
     Removes a PSK contact and its associated state

     - Parameter address: The Algorand address to remove
     */
    public func removeContact(for address: String) async throws {
        try await storage.deleteContact(for: address)
        contactCache.removeValue(forKey: address)
        stateCache.removeValue(forKey: address)
    }

    /**
     Checks if a PSK contact exists for the given address

     - Parameter address: The Algorand address to check
     - Returns: true if a contact exists
     */
    public func hasContact(for address: String) async -> Bool {
        if contactCache[address] != nil {
            return true
        }
        // Check storage
        if let contact = try? await storage.retrieveContact(for: address) {
            contactCache[address] = contact
            return true
        }
        return false
    }

    /**
     Gets a PSK contact for the given address

     - Parameter address: The Algorand address
     - Returns: The PSK contact
     - Throws: `ChatError.pskNotFound` if no contact exists
     */
    public func getContact(for address: String) async throws -> PSKContact {
        if let cached = contactCache[address] {
            return cached
        }
        guard let contact = try await storage.retrieveContact(for: address) else {
            throw ChatError.pskNotFound(address)
        }
        contactCache[address] = contact
        return contact
    }

    /**
     Gets the next send counter and derived PSK for a contact

     - Parameter address: The Algorand address
     - Returns: Tuple of (counter, currentPSK) to use for the next send
     - Throws: `ChatError.pskNotFound` if no contact exists
     */
    public func nextSendCounter(for address: String) async throws -> (counter: UInt32, currentPSK: Data) {
        let contact = try await getContact(for: address)
        let state = try await getState(for: address)

        // Work on a copy so cache is only updated after successful persistence
        var newState = state
        let counter = newState.advanceSendCounter()
        let currentPSK = PSKRatchet.derivePSKAtCounter(
            initialPSK: contact.initialPSK,
            counter: counter
        )

        // Persist before updating cache to avoid desync on failure
        try await storage.storeState(newState, for: address)
        stateCache[address] = newState

        return (counter: counter, currentPSK: currentPSK)
    }

    /**
     Validates a received counter and derives the PSK without recording

     Call `recordReceive(from:counter:)` after successful decryption
     to commit the counter. This prevents burning counters on failed decryptions.

     - Parameters:
       - address: The sender's Algorand address
       - counter: The received ratchet counter
     - Returns: The derived PSK for this counter
     - Throws: `ChatError.pskNotFound`, `ChatError.pskCounterReplay`, or `ChatError.pskCounterOutOfRange`
     */
    public func validateAndDerivePSK(from address: String, counter: UInt32) async throws -> Data {
        let contact = try await getContact(for: address)
        let state = try await getState(for: address)

        try state.validateCounter(counter)

        return PSKRatchet.derivePSKAtCounter(
            initialPSK: contact.initialPSK,
            counter: counter
        )
    }

    /**
     Records a successfully decrypted counter value

     Call this after decryption succeeds to commit the counter
     and persist the updated state.

     - Parameters:
       - address: The sender's Algorand address
       - counter: The received ratchet counter
     */
    public func recordReceive(from address: String, counter: UInt32) async throws {
        var state = try await getState(for: address)
        state.recordReceive(counter)
        try await storage.storeState(state, for: address)
        stateCache[address] = state
    }

    /**
     Lists all PSK contacts

     - Returns: Array of all PSK contacts
     */
    public func listContacts() async throws -> [PSKContact] {
        try await storage.listContacts()
    }

    // MARK: - Private

    /// Gets the ratchet state for a contact, creating a default if not found
    private func getState(for address: String) async throws -> PSKState {
        if let cached = stateCache[address] {
            return cached
        }
        if let stored = try await storage.retrieveState(for: address) {
            stateCache[address] = stored
            return stored
        }
        // Default state
        let state = PSKState()
        stateCache[address] = state
        return state
    }
}
