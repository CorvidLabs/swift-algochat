import Foundation

/// The wire format for encrypted messages stored in transaction notes
///
/// Supports three versions:
///
/// **V1 (Legacy)** - Static key encryption:
/// - Version: 1 byte (0x01)
/// - Protocol: 1 byte (0x01 = AlgoChat v1)
/// - Sender Public Key: 32 bytes (X25519 static)
/// - Nonce: 12 bytes (ChaCha20-Poly1305)
/// - Ciphertext + Tag: remaining bytes
/// - Overhead: 62 bytes (46-byte header + 16-byte tag), max message: 962 bytes
///
/// **V2 (Forward Secrecy)** - Ephemeral key encryption:
/// - Version: 1 byte (0x02)
/// - Protocol: 1 byte (0x01 = AlgoChat)
/// - Sender Static Public Key: 32 bytes (X25519)
/// - Sender Ephemeral Public Key: 32 bytes (X25519)
/// - Nonce: 12 bytes (ChaCha20-Poly1305)
/// - Ciphertext + Tag: remaining bytes
/// - Overhead: 94 bytes (78-byte header + 16-byte tag), max message: 930 bytes
///
/// **V3 (Signed Keys)** - Forward secrecy with key signature:
/// - Version: 1 byte (0x03)
/// - Protocol: 1 byte (0x01 = AlgoChat)
/// - Sender Static Public Key: 32 bytes (X25519)
/// - Sender Ephemeral Public Key: 32 bytes (X25519)
/// - Ed25519 Signature: 64 bytes (signs static key with Algorand account)
/// - Nonce: 12 bytes (ChaCha20-Poly1305)
/// - Ciphertext + Tag: remaining bytes
/// - Overhead: 158 bytes (142-byte header + 16-byte tag), max message: 866 bytes
public struct ChatEnvelope: Sendable {
    // MARK: - Version Constants

    /// Legacy version (static key encryption)
    public static let versionV1: UInt8 = 0x01

    /// Forward secrecy version (ephemeral key encryption)
    public static let versionV2: UInt8 = 0x02

    /// Signed keys version (forward secrecy + key signature)
    public static let versionV3: UInt8 = 0x03

    /// Current default version for new messages
    public static let version: UInt8 = versionV2

    /// Current default version for key publication (with signature)
    public static let keyPublishVersion: UInt8 = versionV3

    /// AlgoChat protocol identifier
    public static let protocolID: UInt8 = 0x01

    // MARK: - Size Constants

    /// Size of the V1 header (version + protocol + static pubkey + nonce)
    public static let headerSizeV1 = 46

    /// Size of the V2 header (version + protocol + static pubkey + ephemeral pubkey + nonce)
    public static let headerSizeV2 = 78

    /// Size of the V3 header (V2 header + 64-byte Ed25519 signature)
    public static let headerSizeV3 = 142

    /// Size of the Ed25519 signature
    public static let signatureSize = 64

    /// Size of the header for current version
    public static let headerSize = headerSizeV2

    /// Size of the Poly1305 authentication tag
    public static let tagSize = 16

    /// Maximum payload size for V1
    public static let maxPayloadSizeV1 = 1024 - headerSizeV1 - tagSize  // 962 bytes

    /// Maximum payload size for V2
    public static let maxPayloadSizeV2 = 1024 - headerSizeV2 - tagSize  // 930 bytes

    /// Maximum payload size for V3
    public static let maxPayloadSizeV3 = 1024 - headerSizeV3 - tagSize  // 866 bytes

    /// Maximum size of the encrypted payload (for current version)
    public static let maxPayloadSize = maxPayloadSizeV2

    // MARK: - Properties

    /// The envelope version (0x01 = legacy, 0x02 = forward secrecy, 0x03 = signed)
    public let envelopeVersion: UInt8

    /// Sender's static X25519 public key (for identity/key discovery)
    public let senderPublicKey: Data

    /// Sender's ephemeral X25519 public key (for forward secrecy, nil in V1)
    public let ephemeralPublicKey: Data?

    /// Ed25519 signature of the static public key (nil in V1/V2, required in V3)
    public let signature: Data?

    /// Nonce used for encryption
    public let nonce: Data

    /// Encrypted message with authentication tag
    public let ciphertext: Data

    /// Whether this envelope uses forward secrecy
    public var usesForwardSecrecy: Bool {
        envelopeVersion >= Self.versionV2 && ephemeralPublicKey != nil
    }

    /// Whether this envelope has a verified key signature
    public var hasSignature: Bool {
        envelopeVersion >= Self.versionV3 && signature != nil
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
        self.signature = nil
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
        self.signature = nil
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Creates a V3 envelope with forward secrecy and key signature
    ///
    /// - Precondition: `senderPublicKey` must be 32 bytes (X25519 public key)
    /// - Precondition: `ephemeralPublicKey` must be 32 bytes (X25519 public key)
    /// - Precondition: `signature` must be 64 bytes (Ed25519 signature)
    /// - Precondition: `nonce` must be 12 bytes (ChaCha20-Poly1305 nonce)
    public init(
        senderPublicKey: Data,
        ephemeralPublicKey: Data,
        signature: Data,
        nonce: Data,
        ciphertext: Data
    ) {
        precondition(senderPublicKey.count == 32, "Sender public key must be 32 bytes")
        precondition(ephemeralPublicKey.count == 32, "Ephemeral public key must be 32 bytes")
        precondition(signature.count == 64, "Signature must be 64 bytes")
        precondition(nonce.count == 12, "Nonce must be 12 bytes")
        self.envelopeVersion = Self.versionV3
        self.senderPublicKey = senderPublicKey
        self.ephemeralPublicKey = ephemeralPublicKey
        self.signature = signature
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Internal initializer for decoding
    private init(
        version: UInt8,
        senderPublicKey: Data,
        ephemeralPublicKey: Data?,
        signature: Data?,
        nonce: Data,
        ciphertext: Data
    ) {
        self.envelopeVersion = version
        self.senderPublicKey = senderPublicKey
        self.ephemeralPublicKey = ephemeralPublicKey
        self.signature = signature
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

        if let sig = signature {
            data.append(sig)
        }

        data.append(nonce)
        data.append(ciphertext)
        return data
    }

    // MARK: - Decoding

    /// Deserializes from transaction note bytes (supports V1, V2, and V3)
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
        case versionV3:
            return try decodeV3(from: data)
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
            signature: nil,
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
            signature: nil,
            nonce: Data(nonce),
            ciphertext: Data(ciphertext)
        )
    }

    /// Decodes a V3 envelope
    private static func decodeV3(from data: Data) throws -> ChatEnvelope {
        guard data.count >= headerSizeV3 + tagSize else {
            throw ChatError.invalidEnvelope("V3 data too short: \(data.count) bytes")
        }

        let senderPublicKey = data[2..<34]
        let ephemeralPublicKey = data[34..<66]
        let signature = data[66..<130]
        let nonce = data[130..<142]
        let ciphertext = data[142...]

        return ChatEnvelope(
            version: versionV3,
            senderPublicKey: Data(senderPublicKey),
            ephemeralPublicKey: Data(ephemeralPublicKey),
            signature: Data(signature),
            nonce: Data(nonce),
            ciphertext: Data(ciphertext)
        )
    }
}
