import Foundation

/**
 File-based persistent storage for the send queue

 Stores pending messages as JSON in `~/.algochat/queue.json`.
 Messages survive app crashes and restarts.

 ## Usage

 ```swift
 let storage = FileSendQueueStorage()
 let queue = SendQueue(storage: storage)

 // Load any pending messages from previous session
 try await queue.load()
 ```
 */
public actor FileSendQueueStorage: SendQueueStorage {
    // MARK: - Constants

    /// Directory name for AlgoChat data
    private static let directoryName = ".algochat"

    /// Filename for the queue
    private static let filename = "queue.json"

    // MARK: - Properties

    /// Custom file URL (for testing)
    private let customURL: URL?

    // MARK: - Initialization

    /// Creates a new file-based queue storage
    ///
    /// - Parameter customURL: Optional custom file URL (for testing)
    public init(customURL: URL? = nil) {
        self.customURL = customURL
    }

    // MARK: - SendQueueStorage

    public func save(_ messages: [PendingMessage]) async throws {
        let url = try queueFileURL()

        if messages.isEmpty {
            // Delete file if queue is empty
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(messages)
        try data.write(to: url, options: .atomic)

        // Set restrictive permissions on Unix
        #if os(Linux) || os(macOS)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        #endif
    }

    public func load() async throws -> [PendingMessage] {
        let url = try queueFileURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([PendingMessage].self, from: data)
    }

    // MARK: - Private

    /// Gets or creates the queue file URL
    private func queueFileURL() throws -> URL {
        if let customURL = customURL {
            return customURL
        }

        let directory = try queueDirectory()
        return directory.appendingPathComponent(Self.filename)
    }

    /// Gets or creates the queue storage directory
    private func queueDirectory() throws -> URL {
        let baseDir: URL

        #if os(Linux)
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            baseDir = URL(fileURLWithPath: home)
        } else {
            baseDir = URL(fileURLWithPath: "/tmp")
        }
        let directory = baseDir.appendingPathComponent(Self.directoryName)
        #elseif os(macOS)
        baseDir = FileManager.default.homeDirectoryForCurrentUser
        let directory = baseDir.appendingPathComponent(Self.directoryName)
        #else
        // iOS, tvOS, watchOS, visionOS - use Application Support directory
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw FileSendQueueStorageError.directoryNotFound
        }
        let directory = appSupport.appendingPathComponent("AlgoChat")
        #endif

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return directory
    }
}

// MARK: - Errors

/// Errors specific to file-based queue storage
public enum FileSendQueueStorageError: Error, LocalizedError {
    case directoryNotFound

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "Could not find application support directory"
        }
    }
}
