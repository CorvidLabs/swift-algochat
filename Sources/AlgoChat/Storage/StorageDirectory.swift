import Foundation

// MARK: - Storage Directory

/// Shared utility for resolving platform-specific storage directories
public enum StorageDirectory {
    /// Default directory name for AlgoChat data
    public static let defaultDirectoryName = ".algochat"

    /// Gets or creates a storage directory with the given name
    /// - Parameter name: Directory name (defaults to ".algochat")
    /// - Returns: URL to the storage directory
    /// - Throws: KeyStorageError.directoryNotFound if directory cannot be determined
    public static func resolve(name: String = defaultDirectoryName) throws -> URL {
        let directory: URL

        #if os(Linux)
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            directory = URL(fileURLWithPath: home).appendingPathComponent(name)
        } else {
            directory = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        }
        #elseif os(macOS)
        directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
        #else
        // iOS, tvOS, watchOS, visionOS - use Application Support directory
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw KeyStorageError.directoryNotFound
        }
        directory = appSupport.appendingPathComponent(name)
        #endif

        if !FileManager.default.fileExists(atPath: directory.path) {
            #if os(Linux) || os(macOS)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            #else
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            #endif
        }

        return directory
    }
}
