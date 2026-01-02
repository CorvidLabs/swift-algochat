import Algorand
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Conversation Merge Tests")
struct ConversationMergeTests {
    // Generate test addresses dynamically for valid checksums
    private let senderAccount = try! Account()
    private let recipientAccount = try! Account()

    // Test helper to create a message
    private func createMessage(
        id: String,
        timestamp: Date,
        direction: Message.Direction = .received
    ) throws -> Message {
        return Message(
            id: id,
            sender: senderAccount.address,
            recipient: recipientAccount.address,
            content: "Test message \(id)",
            timestamp: timestamp,
            confirmedRound: 1000,
            direction: direction
        )
    }

    @Test("Append deduplicates by message ID")
    func testAppendDeduplicatesById() throws {
        var conversation = Conversation(participant: senderAccount.address)

        let message1 = try createMessage(id: "TX001", timestamp: Date())

        // Append same message twice
        conversation.append(message1)
        conversation.append(message1)

        #expect(conversation.messageCount == 1)
    }

    @Test("Append sorts messages by timestamp")
    func testAppendSortsByTimestamp() throws {
        var conversation = Conversation(participant: senderAccount.address)

        let now = Date()
        let earlier = now.addingTimeInterval(-60)
        let later = now.addingTimeInterval(60)

        // Add out of order
        let message2 = try createMessage(id: "TX002", timestamp: now)
        let message1 = try createMessage(id: "TX001", timestamp: earlier)
        let message3 = try createMessage(id: "TX003", timestamp: later)

        conversation.append(message2)
        conversation.append(message1)
        conversation.append(message3)

        #expect(conversation.messages[0].id == "TX001")
        #expect(conversation.messages[1].id == "TX002")
        #expect(conversation.messages[2].id == "TX003")
    }

    @Test("Merge combines messages without duplicates")
    func testMergeCombinesWithoutDuplicates() throws {
        let now = Date()
        let message1 = try createMessage(id: "TX001", timestamp: now)
        let message2 = try createMessage(id: "TX002", timestamp: now.addingTimeInterval(10))
        let message3 = try createMessage(id: "TX003", timestamp: now.addingTimeInterval(20))

        var conversation = Conversation(participant: senderAccount.address, messages: [message1, message2])

        // Merge with overlapping messages
        conversation.merge([message2, message3])

        #expect(conversation.messageCount == 3)
        #expect(conversation.messages.map(\.id) == ["TX001", "TX002", "TX003"])
    }

    @Test("Empty conversation has correct state")
    func testEmptyConversation() throws {
        let conversation = Conversation(participant: senderAccount.address)

        #expect(conversation.isEmpty)
        #expect(conversation.messageCount == 0)
        #expect(conversation.lastMessage == nil)
        #expect(conversation.lastReceived == nil)
        #expect(conversation.lastSent == nil)
    }

    @Test("lastMessage returns most recent message")
    func testLastMessage() throws {
        var conversation = Conversation(participant: senderAccount.address)

        let now = Date()
        conversation.append(try createMessage(id: "TX001", timestamp: now))
        conversation.append(try createMessage(id: "TX002", timestamp: now.addingTimeInterval(60)))

        #expect(conversation.lastMessage?.id == "TX002")
    }

    @Test("lastReceived returns most recent received message")
    func testLastReceived() throws {
        var conversation = Conversation(participant: senderAccount.address)

        let now = Date()
        conversation.append(try createMessage(id: "TX001", timestamp: now, direction: .received))
        conversation.append(try createMessage(id: "TX002", timestamp: now.addingTimeInterval(30), direction: .sent))
        conversation.append(try createMessage(id: "TX003", timestamp: now.addingTimeInterval(60), direction: .received))

        #expect(conversation.lastReceived?.id == "TX003")
    }

    @Test("lastSent returns most recent sent message")
    func testLastSent() throws {
        var conversation = Conversation(participant: senderAccount.address)

        let now = Date()
        conversation.append(try createMessage(id: "TX001", timestamp: now, direction: .sent))
        conversation.append(try createMessage(id: "TX002", timestamp: now.addingTimeInterval(30), direction: .received))
        conversation.append(try createMessage(id: "TX003", timestamp: now.addingTimeInterval(60), direction: .sent))

        #expect(conversation.lastSent?.id == "TX003")
    }

    @Test("receivedMessages filters correctly")
    func testReceivedMessagesFilter() throws {
        var conversation = Conversation(participant: senderAccount.address)

        let now = Date()
        conversation.append(try createMessage(id: "TX001", timestamp: now, direction: .received))
        conversation.append(try createMessage(id: "TX002", timestamp: now.addingTimeInterval(10), direction: .sent))
        conversation.append(try createMessage(id: "TX003", timestamp: now.addingTimeInterval(20), direction: .received))

        let received = conversation.receivedMessages
        #expect(received.count == 2)
        #expect(received.allSatisfy { $0.direction == .received })
    }

    @Test("sentMessages filters correctly")
    func testSentMessagesFilter() throws {
        var conversation = Conversation(participant: senderAccount.address)

        let now = Date()
        conversation.append(try createMessage(id: "TX001", timestamp: now, direction: .sent))
        conversation.append(try createMessage(id: "TX002", timestamp: now.addingTimeInterval(10), direction: .received))
        conversation.append(try createMessage(id: "TX003", timestamp: now.addingTimeInterval(20), direction: .sent))

        let sent = conversation.sentMessages
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.direction == .sent })
    }

    @Test("Conversation identity based on participant")
    func testConversationIdentity() throws {
        let conv1 = Conversation(participant: senderAccount.address)
        let conv2 = Conversation(participant: senderAccount.address)
        let conv3 = Conversation(participant: recipientAccount.address)

        #expect(conv1.id == conv2.id)
        #expect(conv1.id != conv3.id)
    }

    @Test("Merge with empty array does nothing")
    func testMergeEmptyArray() throws {
        let message = try createMessage(id: "TX001", timestamp: Date())
        var conversation = Conversation(participant: senderAccount.address, messages: [message])

        conversation.merge([])

        #expect(conversation.messageCount == 1)
    }

    @Test("Participant encryption key is preserved")
    func testParticipantEncryptionKeyPreserved() throws {
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey

        var conversation = Conversation(
            participant: senderAccount.address,
            participantEncryptionKey: key
        )

        conversation.append(try createMessage(id: "TX001", timestamp: Date()))

        #expect(conversation.participantEncryptionKey?.rawRepresentation == key.rawRepresentation)
    }
}
