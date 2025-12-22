import Foundation

/// Payload for key-publish transactions
///
/// Used to publish an encryption public key without sending an actual message.
/// When decrypted, if the payload has `type: "key-publish"`, it should be
/// filtered out from the message list.
struct KeyPublishPayload: Codable, Sendable {
    let type: String

    init() {
        self.type = "key-publish"
    }

    /// Checks if this is a key-publish payload
    static func isKeyPublish(_ data: Data) -> Bool {
        guard data.first == UInt8(ascii: "{"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return false
        }
        return type == "key-publish"
    }
}

/// Internal structure for message content with optional reply metadata
///
/// Used for structured message encoding. Plain text messages are encoded
/// directly as strings; only messages with reply metadata use JSON encoding.
///
/// Detection: If decrypted content starts with `{` and contains a "text" field,
/// parse as MessagePayload. Otherwise treat as plain text for backward compatibility.
struct MessagePayload: Codable, Sendable {
    /// The message text content
    let text: String

    /// Reply information if this message is a reply
    let replyTo: ReplyInfo?

    /// Information about the message being replied to
    struct ReplyInfo: Codable, Sendable {
        /// Transaction ID of the original message
        let txid: String

        /// Preview of the original message (truncated)
        let preview: String
    }

    init(text: String, replyTo: ReplyInfo? = nil) {
        self.text = text
        self.replyTo = replyTo
    }

    /// Creates a payload for a reply message
    /// - Parameters:
    ///   - text: The reply text
    ///   - originalTxid: Transaction ID of the message being replied to
    ///   - originalPreview: Preview of the original message (will be truncated to 80 chars)
    static func reply(
        text: String,
        originalTxid: String,
        originalPreview: String
    ) -> MessagePayload {
        let truncatedPreview = originalPreview.count > 80
            ? String(originalPreview.prefix(77)) + "..."
            : originalPreview

        return MessagePayload(
            text: text,
            replyTo: ReplyInfo(txid: originalTxid, preview: truncatedPreview)
        )
    }

    /// Formats the message with quoted preview for display
    ///
    /// If this is a reply, includes the quoted original:
    /// ```
    /// > Original message preview...
    ///
    /// Reply text here
    /// ```
    var formattedContent: String {
        guard let replyTo = replyTo else {
            return text
        }
        return "> \(replyTo.preview)\n\n\(text)"
    }
}

/// Result of decrypting a message envelope
public struct DecryptedContent: Sendable {
    /// The message text
    public let text: String

    /// Transaction ID this message replies to (nil if not a reply)
    public let replyToId: String?

    /// Preview of the original message being replied to
    public let replyToPreview: String?

    /// The formatted content including quoted preview for replies
    public let formattedContent: String

    public init(text: String, replyToId: String? = nil, replyToPreview: String? = nil) {
        self.text = text
        self.replyToId = replyToId
        self.replyToPreview = replyToPreview

        // Format with quoted preview if this is a reply
        if let preview = replyToPreview {
            self.formattedContent = "> \(preview)\n\n\(text)"
        } else {
            self.formattedContent = text
        }
    }
}
