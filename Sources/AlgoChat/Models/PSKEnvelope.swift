import Foundation

/**
 The wire format for PSK-mode encrypted messages (protocol v1.1)

 **Format** - Hybrid PSK + ephemeral ECDH:
 - Version: 1 byte (0x01)
 - Protocol: 1 byte (0x02 = AlgoChat PSK)
 - Ratchet Counter: 4 bytes (big-endian UInt32)
 - Sender Static Public Key: 32 bytes (X25519)
 - Ephemeral Public Key: 32 bytes (X25519)
 - Nonce: 12 bytes (ChaCha20-Poly1305)
 - Encrypted Sender Key: 48 bytes (symmetric key encrypted for sender + tag)
 - Ciphertext + Tag: remaining bytes
 - Overhead: 146 bytes (130-byte header + 16-byte tag), max message: 878 bytes
 */
public struct PSKEnvelope: Sendable {
    // MARK: - Constants

    /// Current version
    public static let version: UInt8 = 0x01

    /// PSK protocol identifier
    public static let protocolID: UInt8 = 0x02

    /// Size of the header (version + protocol + counter + static pubkey + ephemeral pubkey + nonce + encrypted sender key)
    public static let headerSize = 130

    /// Size of the encrypted sender key (32-byte key + 16-byte tag)
    public static let encryptedSenderKeySize = 48

    /// Size of the Poly1305 authentication tag
    public static let tagSize = 16

    /// Maximum size of the encrypted payload
    public static let maxPayloadSize = 1024 - headerSize - tagSize  // 878 bytes

    // MARK: - Properties

    /// Ratchet counter for PSK derivation
    public let ratchetCounter: UInt32

    /// Sender's static X25519 public key (for identity/key discovery)
    public let senderPublicKey: Data

    /// Ephemeral X25519 public key (for hybrid key derivation)
    public let ephemeralPublicKey: Data

    /// Nonce used for encryption
    public let nonce: Data

    /// Encrypted symmetric key for sender decryption
    public let encryptedSenderKey: Data

    /// Encrypted message with authentication tag
    public let ciphertext: Data

    // MARK: - Initialization

    /**
     Creates a PSK envelope with hybrid PSK + ephemeral ECDH

     - Precondition: `senderPublicKey` must be 32 bytes (X25519 public key)
     - Precondition: `ephemeralPublicKey` must be 32 bytes (X25519 public key)
     - Precondition: `encryptedSenderKey` must be 48 bytes (32-byte key + 16-byte tag)
     - Precondition: `nonce` must be 12 bytes (ChaCha20-Poly1305 nonce)
     */
    public init(
        ratchetCounter: UInt32,
        senderPublicKey: Data,
        ephemeralPublicKey: Data,
        nonce: Data,
        encryptedSenderKey: Data,
        ciphertext: Data
    ) {
        precondition(senderPublicKey.count == 32, "Sender public key must be 32 bytes")
        precondition(ephemeralPublicKey.count == 32, "Ephemeral public key must be 32 bytes")
        precondition(encryptedSenderKey.count == 48, "Encrypted sender key must be 48 bytes")
        precondition(nonce.count == 12, "Nonce must be 12 bytes")
        self.ratchetCounter = ratchetCounter
        self.senderPublicKey = senderPublicKey
        self.ephemeralPublicKey = ephemeralPublicKey
        self.nonce = nonce
        self.encryptedSenderKey = encryptedSenderKey
        self.ciphertext = ciphertext
    }

    // MARK: - Encoding

    /// Serializes to bytes for transaction note
    public func encode() -> Data {
        var data = Data()
        data.append(Self.version)
        data.append(Self.protocolID)
        // Big-endian counter
        var counter = ratchetCounter.bigEndian
        data.append(Data(bytes: &counter, count: 4))
        data.append(senderPublicKey)
        data.append(ephemeralPublicKey)
        data.append(nonce)
        data.append(encryptedSenderKey)
        data.append(ciphertext)
        return data
    }

    // MARK: - Decoding

    /// Deserializes from transaction note bytes
    public static func decode(from data: Data) throws -> PSKEnvelope {
        guard data.count >= 2 else {
            throw ChatError.invalidEnvelope("Data too short: \(data.count) bytes")
        }

        let versionByte = data[0]
        let protocolByte = data[1]

        guard protocolByte == protocolID else {
            throw ChatError.unsupportedProtocol(protocolByte)
        }

        guard versionByte == version else {
            throw ChatError.unsupportedVersion(versionByte)
        }

        guard data.count >= headerSize + tagSize else {
            throw ChatError.invalidEnvelope("Data too short for PSK envelope: \(data.count) bytes")
        }

        // Parse big-endian counter from bytes [2..<6]
        let ratchetCounter = UInt32(data[2]) << 24
            | UInt32(data[3]) << 16
            | UInt32(data[4]) << 8
            | UInt32(data[5])

        let senderPublicKey = data[6..<38]
        let ephemeralPublicKey = data[38..<70]
        let nonce = data[70..<82]
        let encryptedSenderKey = data[82..<130]
        let ciphertext = data[130...]

        return PSKEnvelope(
            ratchetCounter: ratchetCounter,
            senderPublicKey: Data(senderPublicKey),
            ephemeralPublicKey: Data(ephemeralPublicKey),
            nonce: Data(nonce),
            encryptedSenderKey: Data(encryptedSenderKey),
            ciphertext: Data(ciphertext)
        )
    }
}
