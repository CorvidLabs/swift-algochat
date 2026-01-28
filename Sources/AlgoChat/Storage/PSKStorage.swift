import Foundation

/// Protocol for storing and retrieving PSK contacts and their ratchet state
public protocol PSKStorage: Sendable {
    /**
     Store a PSK contact

     - Parameter contact: The PSK contact to store
     */
    func storeContact(_ contact: PSKContact) async throws

    /**
     Retrieve a PSK contact by address

     - Parameter address: The Algorand address
     - Returns: The stored PSK contact, or nil if not found
     */
    func retrieveContact(for address: String) async throws -> PSKContact?

    /**
     Delete a PSK contact

     - Parameter address: The Algorand address to delete
     */
    func deleteContact(for address: String) async throws

    /**
     List all stored PSK contacts

     - Returns: Array of all stored PSK contacts
     */
    func listContacts() async throws -> [PSKContact]

    /**
     Store the ratchet state for a contact

     - Parameters:
       - state: The PSK state to store
       - address: The Algorand address
     */
    func storeState(_ state: PSKState, for address: String) async throws

    /**
     Retrieve the ratchet state for a contact

     - Parameter address: The Algorand address
     - Returns: The stored PSK state, or nil if not found
     */
    func retrieveState(for address: String) async throws -> PSKState?
}
