import Foundation

/// Errors specific to AlgoChat operations
public enum ChatError: Error, Sendable {
    // MARK: - Encryption Errors

    /// Message exceeds maximum size
    case messageTooLarge(maxSize: Int)

    /// Failed to decrypt message
    case decryptionFailed(String)

    /// Failed to encode message as UTF-8
    case encodingFailed(String)

    /// Failed to generate secure random bytes
    case randomGenerationFailed

    /// Invalid public key format
    case invalidPublicKey(String)

    /// Could not derive encryption keys
    case keyDerivationFailed(String)

    /// Signature verification failed
    case invalidSignature(String)

    // MARK: - Envelope Errors

    /// Invalid message envelope format
    case invalidEnvelope(String)

    /// Unsupported envelope version
    case unsupportedVersion(UInt8)

    /// Unsupported protocol
    case unsupportedProtocol(UInt8)

    // MARK: - Network Errors

    /// Indexer is not configured
    case indexerNotConfigured

    /// Could not find public key for address
    case publicKeyNotFound(String)

    /// Invalid recipient address
    case invalidRecipient(String)

    // MARK: - Transaction Errors

    /// Transaction failed
    case transactionFailed(String)

    /// Insufficient balance
    case insufficientBalance(required: UInt64, available: UInt64)
}

extension ChatError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .messageTooLarge(let maxSize):
            "Message exceeds maximum size of \(maxSize) bytes"
        case .decryptionFailed(let reason):
            "Failed to decrypt message: \(reason)"
        case .encodingFailed(let reason):
            "Failed to encode message: \(reason)"
        case .randomGenerationFailed:
            "Failed to generate secure random bytes"
        case .invalidPublicKey(let reason):
            "Invalid public key: \(reason)"
        case .keyDerivationFailed(let reason):
            "Failed to derive encryption keys: \(reason)"
        case .invalidSignature(let reason):
            "Signature verification failed: \(reason)"
        case .invalidEnvelope(let reason):
            "Invalid message envelope: \(reason)"
        case .unsupportedVersion(let version):
            "Unsupported envelope version: \(version)"
        case .unsupportedProtocol(let proto):
            "Unsupported protocol: \(proto)"
        case .indexerNotConfigured:
            "Indexer client is not configured"
        case .publicKeyNotFound(let address):
            "Could not find public key for address: \(address)"
        case .invalidRecipient(let address):
            "Invalid recipient address: \(address)"
        case .transactionFailed(let reason):
            "Transaction failed: \(reason)"
        case .insufficientBalance(let required, let available):
            "Insufficient balance: need \(required) microAlgos, have \(available)"
        }
    }
}
