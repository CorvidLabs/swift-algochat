import Foundation

/// File-based PSK storage using JSON files
///
/// Stores contacts and state as JSON files in the AlgoChat storage directory:
/// - `{address}.contact.json` for contact information
/// - `{address}.state.json` for ratchet state
public actor FilePSKStorage: PSKStorage {
    // MARK: - Properties

    /// The directory where PSK files are stored
    private let directory: URL

    /// JSON encoder for persistence
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// JSON decoder for reading persisted data
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    /// Creates a file-based PSK storage
    ///
    /// - Parameter directoryName: The storage directory name (defaults to ".algochat")
    /// - Throws: If the directory cannot be created
    public init(directoryName: String = StorageDirectory.defaultDirectoryName) throws {
        let baseDir = try StorageDirectory.resolve(name: directoryName)
        self.directory = baseDir.appendingPathComponent("psk")

        if !FileManager.default.fileExists(atPath: self.directory.path) {
            #if os(Linux) || os(macOS)
            try FileManager.default.createDirectory(
                at: self.directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            #else
            try FileManager.default.createDirectory(
                at: self.directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            #endif
        }
    }

    // MARK: - PSKStorage

    public func storeContact(_ contact: PSKContact) async throws {
        let url = contactURL(for: contact.address)
        let data = try encoder.encode(contact)
        try data.write(to: url, options: .atomic)
    }

    public func retrieveContact(for address: String) async throws -> PSKContact? {
        let url = contactURL(for: address)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(PSKContact.self, from: data)
    }

    public func deleteContact(for address: String) async throws {
        let contactFile = contactURL(for: address)
        let stateFile = stateURL(for: address)

        if FileManager.default.fileExists(atPath: contactFile.path) {
            try FileManager.default.removeItem(at: contactFile)
        }
        if FileManager.default.fileExists(atPath: stateFile.path) {
            try FileManager.default.removeItem(at: stateFile)
        }
    }

    public func listContacts() async throws -> [PSKContact] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        var contacts: [PSKContact] = []
        for file in files where file.lastPathComponent.hasSuffix(".contact.json") {
            let data = try Data(contentsOf: file)
            let contact = try decoder.decode(PSKContact.self, from: data)
            contacts.append(contact)
        }

        return contacts
    }

    public func storeState(_ state: PSKState, for address: String) async throws {
        let url = stateURL(for: address)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    public func retrieveState(for address: String) async throws -> PSKState? {
        let url = stateURL(for: address)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(PSKState.self, from: data)
    }

    // MARK: - Private

    /// Returns the file URL for a contact's data
    private func contactURL(for address: String) -> URL {
        directory.appendingPathComponent("\(address).contact.json")
    }

    /// Returns the file URL for a contact's ratchet state
    private func stateURL(for address: String) -> URL {
        directory.appendingPathComponent("\(address).state.json")
    }
}
