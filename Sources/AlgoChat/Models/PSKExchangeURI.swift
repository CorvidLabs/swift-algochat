import Foundation

/// Represents a PSK exchange URI for out-of-band key exchange
///
/// Format: `algochat-psk://v1?addr=...&psk=...&label=...`
/// The PSK is encoded using base64url (RFC 4648).
public struct PSKExchangeURI: Sendable, Equatable {
    /// The contact's Algorand address
    public let address: String

    /// The 32-byte pre-shared key
    public let psk: Data

    /// Optional label for the contact
    public let label: String?

    // MARK: - Initialization

    /// Creates a new PSK exchange URI
    ///
    /// - Parameters:
    ///   - address: The Algorand address
    ///   - psk: The 32-byte pre-shared key
    ///   - label: Optional human-readable label
    public init(address: String, psk: Data, label: String? = nil) {
        precondition(psk.count == 32, "PSK must be 32 bytes")
        self.address = address
        self.psk = psk
        self.label = label
    }

    // MARK: - Encoding

    /// Generates the URI string
    public func toString() -> String {
        var components = URLComponents()
        components.scheme = "algochat-psk"
        components.host = "v1"

        var queryItems = [
            URLQueryItem(name: "addr", value: address),
            URLQueryItem(name: "psk", value: base64urlEncode(psk))
        ]

        if let label {
            queryItems.append(URLQueryItem(name: "label", value: label))
        }

        components.queryItems = queryItems
        return components.string ?? ""
    }

    // MARK: - Parsing

    /// Parses a PSK exchange URI string
    ///
    /// - Parameter string: The URI string to parse
    /// - Returns: A parsed PSKExchangeURI
    /// - Throws: `ChatError.invalidEnvelope` if the URI is invalid
    public static func parse(_ string: String) throws -> PSKExchangeURI {
        guard let components = URLComponents(string: string) else {
            throw ChatError.invalidEnvelope("Invalid PSK exchange URI")
        }

        guard components.scheme == "algochat-psk" else {
            throw ChatError.invalidEnvelope("Invalid scheme: expected algochat-psk")
        }

        guard components.host == "v1" else {
            throw ChatError.invalidEnvelope("Unsupported PSK URI version")
        }

        let queryItems = components.queryItems ?? []

        guard let addrItem = queryItems.first(where: { $0.name == "addr" }),
              let addr = addrItem.value,
              !addr.isEmpty else {
            throw ChatError.invalidEnvelope("Missing addr parameter in PSK URI")
        }

        guard let pskItem = queryItems.first(where: { $0.name == "psk" }),
              let pskString = pskItem.value,
              let pskData = base64urlDecode(pskString),
              pskData.count == 32 else {
            throw ChatError.invalidEnvelope("Missing or invalid psk parameter in PSK URI")
        }

        let label = queryItems.first(where: { $0.name == "label" })?.value

        return PSKExchangeURI(address: addr, psk: pskData, label: label)
    }

    // MARK: - Base64url Helpers

    /// Encodes data to base64url (RFC 4648)
    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes base64url (RFC 4648) to data
    private static func base64urlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Add padding
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    /// Instance method for encoding
    private func base64urlEncode(_ data: Data) -> String {
        Self.base64urlEncode(data)
    }
}
