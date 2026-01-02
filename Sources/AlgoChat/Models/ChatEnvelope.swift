import Foundation

/// The wire format for encrypted messages stored in transaction notes
///
/// Supports two versions:
///
/// **V1 (Legacy)** - Static key encryption:
/// - Version: 1 byte (0x01)
/// - Protocol: 1 byte (0x01 = AlgoChat v1)
/// - Sender Public Key: 32 bytes (X25519 static)
/// - Nonce: 12 bytes (ChaCha20-Poly1305)
/// - Ciphertext + Tag: remaining bytes
/// - Overhead: 62 bytes, max message: 962 bytes
///
/// **V2 (Forward Secrecy)** - Ephemeral key encryption:
/// - Version: 1 byte (0x02)
/// - Protocol: 1 byte (0x01 = AlgoChat)
/// - Sender Static Public Key: 32 bytes (X25519)
/// - Sender Ephemeral Public Key: 32 bytes (X25519)
/// - Nonce: 12 bytes (ChaCha20-Poly1305)
/// - Ciphertext + Tag: remaining bytes
/// - Overhead: 94 bytes, max message: 930 bytes
public struct ChatEnvelope: Sendable {
    // MARK: - Version Constants

    /// Legacy version (static key encryption)
    public static let versionV1: UInt8 = 0x01

    /// Forward secrecy version (ephemeral key encryption)
    public static let versionV2: UInt8 = 0x02

    /// Current default version for new messages
    public static let version: UInt8 = versionV2

    /// AlgoChat protocol identifier
    public static let protocolID: UInt8 = 0x01

    // MARK: - Size Constants

    /// Size of the V1 header (version + protocol + static pubkey + nonce)
    public static let headerSizeV1 = 46

    /// Size of the V2 header (version + protocol + static pubkey + ephemeral pubkey + nonce)
    public static let headerSizeV2 = 78

    /// Size of the header for current version
    public static let headerSize = headerSizeV2

    /// Size of the Poly1305 authentication tag
    public static let tagSize = 16

    /// Maximum payload size for V1
    public static let maxPayloadSizeV1 = 1024 - headerSizeV1 - tagSize  // 962 bytes

    /// Maximum payload size for V2
    public static let maxPayloadSizeV2 = 1024 - headerSizeV2 - tagSize  // 930 bytes

    /// Maximum size of the encrypted payload (for current version)
    public static let maxPayloadSize = maxPayloadSizeV2

    // MARK: - Properties

    /// The envelope version (0x01 = legacy, 0x02 = forward secrecy)
    public let envelopeVersion: UInt8

    /// Sender's static X25519 public key (for identity/key discovery)
    public let senderPublicKey: Data

    /// Sender's ephemeral X25519 public key (for forward secrecy, nil in V1)
    public let ephemeralPublicKey: Data?

    /// Nonce used for encryption
    public let nonce: Data

    /// Encrypted message with authentication tag
    public let ciphertext: Data

    /// Whether this envelope uses forward secrecy
    public var usesForwardSecrecy: Bool {
        envelopeVersion >= Self.versionV2 && ephemeralPublicKey != nil
    }

    // MARK: - Initialization

    /// Creates a V1 envelope (legacy, no forward secrecy)
    ///
    /// - Precondition: `senderPublicKey` must be 32 bytes (X25519 public key)
    /// - Precondition: `nonce` must be 12 bytes (ChaCha20-Poly1305 nonce)
    public init(senderPublicKey: Data, nonce: Data, ciphertext: Data) {
        precondition(senderPublicKey.count == 32, "Sender public key must be 32 bytes")
        precondition(nonce.count == 12, "Nonce must be 12 bytes")
        self.envelopeVersion = Self.versionV1
        self.senderPublicKey = senderPublicKey
        self.ephemeralPublicKey = nil
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Creates a V2 envelope with forward secrecy
    ///
    /// - Precondition: `senderPublicKey` must be 32 bytes (X25519 public key)
    /// - Precondition: `ephemeralPublicKey` must be 32 bytes (X25519 public key)
    /// - Precondition: `nonce` must be 12 bytes (ChaCha20-Poly1305 nonce)
    public init(
        senderPublicKey: Data,
        ephemeralPublicKey: Data,
        nonce: Data,
        ciphertext: Data
    ) {
        precondition(senderPublicKey.count == 32, "Sender public key must be 32 bytes")
        precondition(ephemeralPublicKey.count == 32, "Ephemeral public key must be 32 bytes")
        precondition(nonce.count == 12, "Nonce must be 12 bytes")
        self.envelopeVersion = Self.versionV2
        self.senderPublicKey = senderPublicKey
        self.ephemeralPublicKey = ephemeralPublicKey
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Internal initializer for decoding
    private init(
        version: UInt8,
        senderPublicKey: Data,
        ephemeralPublicKey: Data?,
        nonce: Data,
        ciphertext: Data
    ) {
        self.envelopeVersion = version
        self.senderPublicKey = senderPublicKey
        self.ephemeralPublicKey = ephemeralPublicKey
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    // MARK: - Encoding

    /// Serializes to bytes for transaction note
    public func encode() -> Data {
        var data = Data()
        data.append(envelopeVersion)
        data.append(Self.protocolID)
        data.append(senderPublicKey)

        if let ephemeralKey = ephemeralPublicKey {
            data.append(ephemeralKey)
        }

        data.append(nonce)
        data.append(ciphertext)
        return data
    }

    // MARK: - Decoding

    /// Deserializes from transaction note bytes (supports V1 and V2)
    public static func decode(from data: Data) throws -> ChatEnvelope {
        guard data.count >= 2 else {
            throw ChatError.invalidEnvelope("Data too short: \(data.count) bytes")
        }

        let version = data[0]
        let protocolByte = data[1]

        guard protocolByte == protocolID else {
            throw ChatError.unsupportedProtocol(protocolByte)
        }

        switch version {
        case versionV1:
            return try decodeV1(from: data)
        case versionV2:
            return try decodeV2(from: data)
        default:
            throw ChatError.unsupportedVersion(version)
        }
    }

    /// Decodes a V1 envelope
    private static func decodeV1(from data: Data) throws -> ChatEnvelope {
        guard data.count >= headerSizeV1 + tagSize else {
            throw ChatError.invalidEnvelope("V1 data too short: \(data.count) bytes")
        }

        let senderPublicKey = data[2..<34]
        let nonce = data[34..<46]
        let ciphertext = data[46...]

        return ChatEnvelope(
            version: versionV1,
            senderPublicKey: Data(senderPublicKey),
            ephemeralPublicKey: nil,
            nonce: Data(nonce),
            ciphertext: Data(ciphertext)
        )
    }

    /// Decodes a V2 envelope
    private static func decodeV2(from data: Data) throws -> ChatEnvelope {
        guard data.count >= headerSizeV2 + tagSize else {
            throw ChatError.invalidEnvelope("V2 data too short: \(data.count) bytes")
        }

        let senderPublicKey = data[2..<34]
        let ephemeralPublicKey = data[34..<66]
        let nonce = data[66..<78]
        let ciphertext = data[78...]

        return ChatEnvelope(
            version: versionV2,
            senderPublicKey: Data(senderPublicKey),
            ephemeralPublicKey: Data(ephemeralPublicKey),
            nonce: Data(nonce),
            ciphertext: Data(ciphertext)
        )
    }
}
