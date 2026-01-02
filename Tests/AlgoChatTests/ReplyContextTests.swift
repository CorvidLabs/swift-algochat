@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Reply Context Tests")
struct ReplyContextTests {
    @Test("Reply context preserves message ID")
    func testReplyContextPreservesId() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let originalTxid = "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCD"

        let envelope = try MessageEncryptor.encrypt(
            message: "My reply",
            replyTo: (txid: originalTxid, preview: "Original message"),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.replyToId == originalTxid)
    }

    @Test("Reply preview truncates at 80 characters")
    func testReplyPreviewTruncatesAt80Chars() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Create a message longer than 80 chars
        let longPreview = String(repeating: "a", count: 100)

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply",
            replyTo: (txid: "TX123", preview: longPreview),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.replyToPreview?.count == 80)
        #expect(decrypted.replyToPreview?.hasSuffix("...") == true)
    }

    @Test("Reply preview keeps short messages intact")
    func testReplyPreviewKeepsShortMessagesIntact() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let shortPreview = "Short message"

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply",
            replyTo: (txid: "TX123", preview: shortPreview),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.replyToPreview == shortPreview)
    }

    @Test("Reply preview handles exactly 80 characters")
    func testReplyPreviewExactly80Chars() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Exactly 80 characters should not be truncated
        let exactPreview = String(repeating: "x", count: 80)

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply",
            replyTo: (txid: "TX123", preview: exactPreview),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.replyToPreview == exactPreview)
        #expect(decrypted.replyToPreview?.hasSuffix("...") == false)
    }

    @Test("Reply preview handles 81 characters (just over limit)")
    func testReplyPreview81Chars() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // 81 characters should be truncated
        let slightlyLongPreview = String(repeating: "y", count: 81)

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply",
            replyTo: (txid: "TX123", preview: slightlyLongPreview),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.replyToPreview?.count == 80)
        #expect(decrypted.replyToPreview?.hasSuffix("...") == true)
    }

    @Test("Reply formatted content includes quoted preview")
    func testReplyFormattedContentIncludesQuote() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "I agree!",
            replyTo: (txid: "TX123", preview: "What do you think?"),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        // formattedContent should include the quoted original
        #expect(decrypted.formattedContent.contains("> What do you think?"))
        #expect(decrypted.formattedContent.contains("I agree!"))
    }

    @Test("Reply handles empty preview gracefully")
    func testReplyEmptyPreview() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply to empty",
            replyTo: (txid: "TX123", preview: ""),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.text == "Reply to empty")
        #expect(decrypted.replyToId == "TX123")
        #expect(decrypted.replyToPreview == "")
    }

    @Test("Reply preview handles Unicode properly")
    func testReplyPreviewUnicode() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let unicodePreview = "Hello 你好 مرحبا שלום 🎉🚀"

        let envelope = try MessageEncryptor.encrypt(
            message: "Reply!",
            replyTo: (txid: "TX123", preview: unicodePreview),
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.replyToPreview == unicodePreview)
    }

    @Test("Non-reply message has nil reply context")
    func testNonReplyHasNilContext() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        let envelope = try MessageEncryptor.encrypt(
            message: "Just a regular message",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        guard let decrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: recipientKey
        ) else {
            Issue.record("Expected non-nil decrypted content")
            return
        }

        #expect(decrypted.replyToId == nil)
        #expect(decrypted.replyToPreview == nil)
    }
}
