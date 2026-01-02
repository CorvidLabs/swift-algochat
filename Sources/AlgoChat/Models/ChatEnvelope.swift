import Foundation

/// The wire format for encrypted messages stored in transaction notes
///
/// Binary format (to maximize space for message content):
/// - Version: 1 byte (0x01)
/// - Protocol: 1 byte (0x01 = AlgoChat v1)
/// - Sender Public Key: 32 bytes (X25519)
/// - Nonce: 12 bytes (ChaCha20-Poly1305)
/// - Ciphertext + Tag: remaining bytes (message + 16-byte auth tag)
///
/// Total overhead: 1 + 1 + 32 + 12 + 16 = 62 bytes
/// Max message size: 1024 - 62 = 962 bytes
public struct ChatEnvelope: Sendable {
    /// Current envelope version
    public static let version: UInt8 = 0x01

    /// AlgoChat protocol identifier
    public static let protocolID: UInt8 = 0x01

    /// Size of the header (version + protocol + pubkey + nonce)
    public static let headerSize = 46

    /// Size of the Poly1305 authentication tag
    public static let tagSize = 16

    /// Maximum size of the encrypted payload (message bytes)
    public static let maxPayloadSize = 1024 - headerSize - tagSize  // 962 bytes

    /// Sender's X25519 public key (for recipient to derive shared secret)
    public let senderPublicKey: Data

    /// Nonce used for encryption
    public let nonce: Data

    /// Encrypted message with authentication tag
    public let ciphertext: Data

    public init(senderPublicKey: Data, nonce: Data, ciphertext: Data) {
        self.senderPublicKey = senderPublicKey
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Serializes to bytes for transaction note
    public func encode() -> Data {
        var data = Data()
        data.append(Self.version)
        data.append(Self.protocolID)
        data.append(senderPublicKey)
        data.append(nonce)
        data.append(ciphertext)
        return data
    }

    /// Deserializes from transaction note bytes
    public static func decode(from data: Data) throws -> ChatEnvelope {
        guard data.count >= headerSize + tagSize else {
            throw ChatError.invalidEnvelope("Data too short: \(data.count) bytes")
        }

        guard data[0] == version else {
            throw ChatError.unsupportedVersion(data[0])
        }

        guard data[1] == protocolID else {
            throw ChatError.unsupportedProtocol(data[1])
        }

        let senderPublicKey = data[2..<34]
        let nonce = data[34..<46]
        let ciphertext = data[46...]

        return ChatEnvelope(
            senderPublicKey: Data(senderPublicKey),
            nonce: Data(nonce),
            ciphertext: Data(ciphertext)
        )
    }
}
