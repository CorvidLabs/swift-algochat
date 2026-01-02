import Algorand
import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("ChatEnvelope Validation Tests")
struct ChatEnvelopeValidationTests {
    @Test("Valid chat envelope has correct header bytes")
    func testValidEnvelopeHeader() throws {
        let envelope = ChatEnvelope(
            senderPublicKey: Data(repeating: 0x01, count: 32),
            nonce: Data(repeating: 0x02, count: 12),
            ciphertext: Data(repeating: 0x03, count: 50)
        )
        let encoded = envelope.encode()

        // First two bytes should be version and protocol
        #expect(encoded[0] == ChatEnvelope.version)
        #expect(encoded[1] == ChatEnvelope.protocolID)
        #expect(encoded.count >= ChatEnvelope.headerSize)
    }

    @Test("Envelope with minimum payload size")
    func testMinimumPayloadSize() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Single character message
        let envelope = try MessageEncryptor.encrypt(
            message: "x",
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let encoded = envelope.encode()
        #expect(encoded.count >= ChatEnvelope.headerSize + ChatEnvelope.tagSize + 1)
    }

    @Test("Envelope at maximum payload size")
    func testMaximumPayloadSize() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Create message at exactly max size
        let maxMessage = String(repeating: "x", count: ChatEnvelope.maxPayloadSize)

        let envelope = try MessageEncryptor.encrypt(
            message: maxMessage,
            senderPrivateKey: senderKey,
            recipientPublicKey: recipientKey.publicKey
        )

        let encoded = envelope.encode()
        #expect(encoded.count <= 1024)  // Algorand note field limit
    }

    @Test("Envelope rejects payload over maximum size")
    func testRejectsOversizedPayload() throws {
        let senderKey = Curve25519.KeyAgreement.PrivateKey()
        let recipientKey = Curve25519.KeyAgreement.PrivateKey()

        // Create message over max size
        let oversizedMessage = String(repeating: "x", count: ChatEnvelope.maxPayloadSize + 100)

        #expect(throws: ChatError.self) {
            _ = try MessageEncryptor.encrypt(
                message: oversizedMessage,
                senderPrivateKey: senderKey,
                recipientPublicKey: recipientKey.publicKey
            )
        }
    }
}

@Suite("Message Direction Tests")
struct MessageDirectionTests {
    // Generate test addresses dynamically for valid checksums
    private let senderAccount = try! Account()
    private let recipientAccount = try! Account()

    @Test("Message direction enum values")
    func testDirectionEnumValues() throws {
        #expect(Message.Direction.sent.rawValue == "sent")
        #expect(Message.Direction.received.rawValue == "received")
    }

    @Test("Message direction is preserved in roundtrip")
    func testDirectionPreservedInMessage() throws {
        let sentMessage = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Hello",
            timestamp: Date(),
            confirmedRound: 1000,
            direction: .sent
        )

        let receivedMessage = Message(
            id: "TX002",
            sender: recipientAccount.address,
            recipient: senderAccount.address,
            content: "Hi back",
            timestamp: Date(),
            confirmedRound: 1001,
            direction: .received
        )

        #expect(sentMessage.direction == .sent)
        #expect(receivedMessage.direction == .received)
    }
}

@Suite("Message Equality Tests")
struct MessageEqualityTests {
    // Generate test addresses dynamically for valid checksums
    private let senderAccount = try! Account()
    private let recipientAccount = try! Account()

    @Test("Messages with same ID are equal")
    func testMessagesWithSameIdAreEqual() throws {
        let message1 = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Hello",
            timestamp: Date(),
            confirmedRound: 1000,
            direction: .sent
        )

        let message2 = Message(
            id: "TX001",
            sender: recipientAccount.address,  // Different sender
            recipient: senderAccount.address,
            content: "Different content",  // Different content
            timestamp: Date().addingTimeInterval(100),  // Different time
            confirmedRound: 2000,  // Different round
            direction: .received  // Different direction
        )

        #expect(message1 == message2)  // Same ID = equal
    }

    @Test("Messages with different IDs are not equal")
    func testMessagesWithDifferentIdsAreNotEqual() throws {
        let now = Date()

        let message1 = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Hello",
            timestamp: now,
            confirmedRound: 1000,
            direction: .sent
        )

        let message2 = Message(
            id: "TX002",  // Different ID
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Hello",  // Same content
            timestamp: now,  // Same time
            confirmedRound: 1000,  // Same round
            direction: .sent  // Same direction
        )

        #expect(message1 != message2)
    }

    @Test("Message hash is based on ID")
    func testMessageHashBasedOnId() throws {
        let message1 = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Hello",
            timestamp: Date(),
            confirmedRound: 1000,
            direction: .sent
        )

        let message2 = Message(
            id: "TX001",
            sender: recipientAccount.address,
            recipient: senderAccount.address,
            content: "Different",
            timestamp: Date().addingTimeInterval(100),
            confirmedRound: 2000,
            direction: .received
        )

        // Same ID = same hash
        #expect(message1.hashValue == message2.hashValue)

        // Can use in Set
        var messageSet = Set<Message>()
        messageSet.insert(message1)
        messageSet.insert(message2)
        #expect(messageSet.count == 1)  // Only one message (same ID)
    }
}

@Suite("Message Codable Tests")
struct MessageCodableTests {
    // Generate test addresses dynamically for valid checksums
    private let senderAccount = try! Account()
    private let recipientAccount = try! Account()

    @Test("Message encodes and decodes correctly")
    func testMessageCodableRoundTrip() throws {
        let original = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Test message with 你好 emoji ",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            confirmedRound: 12345,
            direction: .sent,
            replyContext: ReplyContext(messageId: "TX000", preview: "Previous message")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Message.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.sender == original.sender)
        #expect(decoded.recipient == original.recipient)
        #expect(decoded.content == original.content)
        #expect(decoded.confirmedRound == original.confirmedRound)
        #expect(decoded.direction == original.direction)
        #expect(decoded.replyContext?.messageId == original.replyContext?.messageId)
        #expect(decoded.replyContext?.preview == original.replyContext?.preview)
    }

    @Test("Message without reply context encodes correctly")
    func testMessageWithoutReplyContext() throws {
        let original = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Simple message",
            timestamp: Date(),
            confirmedRound: 1000,
            direction: .received,
            replyContext: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Message.self, from: data)

        #expect(decoded.replyContext == nil)
        #expect(decoded.isReply == false)
    }
}

@Suite("ReplyContext Tests")
struct ReplyContextModelTests {
    // Generate test addresses dynamically for valid checksums
    private let senderAccount = try! Account()
    private let recipientAccount = try! Account()

    @Test("ReplyContext from message truncates long content")
    func testReplyContextFromMessageTruncates() throws {
        let longContent = String(repeating: "a", count: 100)
        let message = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: longContent,
            timestamp: Date(),
            confirmedRound: 1000,
            direction: .received
        )

        let context = ReplyContext(replyingTo: message)

        #expect(context.messageId == "TX001")
        #expect(context.preview.count == 80)
        #expect(context.preview.hasSuffix("..."))
    }

    @Test("ReplyContext from message preserves short content")
    func testReplyContextFromMessagePreservesShort() throws {
        let shortContent = "Short message"
        let message = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: shortContent,
            timestamp: Date(),
            confirmedRound: 1000,
            direction: .received
        )

        let context = ReplyContext(replyingTo: message)

        #expect(context.preview == shortContent)
    }

    @Test("ReplyContext is Codable")
    func testReplyContextCodable() throws {
        let original = ReplyContext(messageId: "TX123", preview: "Original message")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReplyContext.self, from: data)

        #expect(decoded.messageId == original.messageId)
        #expect(decoded.preview == original.preview)
    }

    @Test("ReplyContext is Equatable")
    func testReplyContextEquatable() throws {
        let context1 = ReplyContext(messageId: "TX123", preview: "Hello")
        let context2 = ReplyContext(messageId: "TX123", preview: "Hello")
        let context3 = ReplyContext(messageId: "TX456", preview: "Hello")

        #expect(context1 == context2)
        #expect(context1 != context3)
    }

    @Test("ReplyContext custom max length")
    func testReplyContextCustomMaxLength() throws {
        let content = String(repeating: "x", count: 100)
        let message = Message(
            id: "TX001",
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: content,
            timestamp: Date(),
            confirmedRound: 1000,
            direction: .received
        )

        let context = ReplyContext(replyingTo: message, maxLength: 50)

        #expect(context.preview.count == 50)
        #expect(context.preview.hasSuffix("..."))
    }
}
