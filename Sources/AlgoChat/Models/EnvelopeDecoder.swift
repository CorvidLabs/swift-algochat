import Foundation

/**
 Unified entry point for decoding encrypted envelopes

 Inspects the protocol byte and dispatches to the correct envelope type.
 */
public enum EnvelopeDecoder {
    /// A decoded envelope, either standard or PSK
    public enum DecodedEnvelope: Sendable {
        /// Standard mode envelope (protocol 0x01)
        case standard(ChatEnvelope)

        /// PSK ratcheting mode envelope (protocol 0x02)
        case psk(PSKEnvelope)
    }

    /**
     Decodes raw data into the appropriate envelope type

     - Parameter data: The raw envelope bytes
     - Returns: A decoded envelope
     - Throws: `ChatError` if the data is invalid
     */
    public static func decode(from data: Data) throws -> DecodedEnvelope {
        guard data.count >= 2 else {
            throw ChatError.invalidEnvelope("Data too short: \(data.count) bytes")
        }

        let protocolByte = data[1]

        switch protocolByte {
        case ChatEnvelope.protocolID:
            let envelope = try ChatEnvelope.decode(from: data)
            return .standard(envelope)

        case PSKEnvelope.protocolID:
            let envelope = try PSKEnvelope.decode(from: data)
            return .psk(envelope)

        default:
            throw ChatError.unsupportedProtocol(protocolByte)
        }
    }

    /**
     Checks if raw data is a valid AlgoChat message (either standard or PSK)

     - Parameter data: The raw data to check
     - Returns: true if this is a recognized AlgoChat envelope
     */
    public static func isChatMessage(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let version = data[0]
        let protocolByte = data[1]
        return version == ChatEnvelope.version
            && (protocolByte == ChatEnvelope.protocolID || protocolByte == PSKEnvelope.protocolID)
    }
}
