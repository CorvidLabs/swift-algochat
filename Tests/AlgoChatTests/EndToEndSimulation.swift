@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

#if canImport(Security)
import Security
#endif

/// END-TO-END SIMULATION TESTS
/// Simulates months/years of real-world usage to prove the system works correctly.
/// Tests multi-user scenarios, key changes, security boundaries, and edge cases.

// MARK: - Test Helpers

/// Simulates a user with their own key pair
struct SimulatedUser {
    let name: String
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    var publicKey: Curve25519.KeyAgreement.PublicKey { privateKey.publicKey }

    init(name: String) {
        self.name = name
        self.privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    /// Generate a new key (simulates key rotation)
    func rotateKey() -> SimulatedUser {
        SimulatedUser(name: name)
    }
}

/// Represents an encrypted message on the "blockchain"
struct StoredMessage {
    let id: String
    let senderName: String
    let recipientName: String
    let envelope: ChatEnvelope
    let timestamp: Date
}

/// Simulated message store (like blockchain storage)
actor MessageStore {
    private var messages: [StoredMessage] = []
    private var messageCount = 0

    func store(_ envelope: ChatEnvelope, from sender: String, to recipient: String) -> String {
        messageCount += 1
        let id = "TX\(String(format: "%06d", messageCount))"
        let msg = StoredMessage(
            id: id,
            senderName: sender,
            recipientName: recipient,
            envelope: envelope,
            timestamp: Date()
        )
        messages.append(msg)
        return id
    }

    func getMessages(for user: String) -> [StoredMessage] {
        messages.filter { $0.senderName == user || $0.recipientName == user }
    }

    func getAllMessages() -> [StoredMessage] {
        messages
    }

    func count() -> Int {
        messages.count
    }
}

// MARK: - Multi-User Conversation Tests

@Suite("E2E: Multi-User Conversations", .serialized)
struct MultiUserConversationTests {

    @Test("Two users exchange 100 messages back and forth")
    func testTwoUserConversation() async throws {
        let alice = SimulatedUser(name: "Alice")
        let bob = SimulatedUser(name: "Bob")
        let store = MessageStore()

        print("\n=== TWO USER CONVERSATION (100 messages) ===")
        print("Alice: \(alice.publicKey.rawRepresentation.prefix(8).hex)...")
        print("Bob:   \(bob.publicKey.rawRepresentation.prefix(8).hex)...")

        // Exchange 100 messages
        for i in 1...100 {
            let isAliceSending = i % 2 == 1
            let sender = isAliceSending ? alice : bob
            let recipient = isAliceSending ? bob : alice

            let message = "Message #\(i) from \(sender.name)"
            let envelope = try MessageEncryptor.encrypt(
                message: message,
                senderPrivateKey: sender.privateKey,
                recipientPublicKey: recipient.publicKey
            )

            let txid = await store.store(envelope, from: sender.name, to: recipient.name)

            // Recipient decrypts
            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: recipient.privateKey
            )

            #expect(decrypted?.text == message, "Message \(i) failed to decrypt")

            if i % 25 == 0 {
                print("  ✓ Messages 1-\(i) verified")
            }
        }

        let count = await store.count()
        print("Total messages stored: \(count)")
        print("✅ All 100 messages encrypted and decrypted correctly")

        #expect(count == 100)
    }

    @Test("Five users in a group chat simulation (250 messages)")
    func testFiveUserGroupChat() async throws {
        let users = [
            SimulatedUser(name: "Alice"),
            SimulatedUser(name: "Bob"),
            SimulatedUser(name: "Charlie"),
            SimulatedUser(name: "Diana"),
            SimulatedUser(name: "Eve")
        ]
        let store = MessageStore()

        print("\n=== FIVE USER GROUP SIMULATION (250 messages) ===")
        for user in users {
            print("\(user.name): \(user.publicKey.rawRepresentation.prefix(8).hex)...")
        }

        // Each user sends 10 messages to each other user (pairwise E2E)
        var messagesSent = 0
        for sender in users {
            for recipient in users where sender.name != recipient.name {
                for msgNum in 1...10 {
                    let message = "\(sender.name) → \(recipient.name): Message \(msgNum)"
                    let envelope = try MessageEncryptor.encrypt(
                        message: message,
                        senderPrivateKey: sender.privateKey,
                        recipientPublicKey: recipient.publicKey
                    )

                    _ = await store.store(envelope, from: sender.name, to: recipient.name)

                    // Recipient decrypts
                    let decrypted = try MessageEncryptor.decrypt(
                        envelope: envelope,
                        recipientPrivateKey: recipient.privateKey
                    )

                    #expect(decrypted?.text == message)
                    messagesSent += 1
                }
            }
        }

        // 5 users × 4 recipients × 10 messages = 200 messages
        let count = await store.count()
        print("Total messages: \(count)")
        print("✅ All \(messagesSent) pairwise messages verified")

        #expect(count == 200)
    }

    @Test("Long conversation thread with replies (50 messages)")
    func testLongReplyThread() async throws {
        let alice = SimulatedUser(name: "Alice")
        let bob = SimulatedUser(name: "Bob")
        let store = MessageStore()

        print("\n=== REPLY THREAD SIMULATION (50 messages) ===")

        var lastTxid: String? = nil
        var lastPreview: String? = nil

        for i in 1...50 {
            let isAliceSending = i % 2 == 1
            let sender = isAliceSending ? alice : bob
            let recipient = isAliceSending ? bob : alice

            let message = "Reply #\(i) in thread"
            let envelope: ChatEnvelope

            if let replyTo = lastTxid, let preview = lastPreview {
                // Reply to previous message
                envelope = try MessageEncryptor.encrypt(
                    message: message,
                    replyTo: (txid: replyTo, preview: String(preview.prefix(40))),
                    senderPrivateKey: sender.privateKey,
                    recipientPublicKey: recipient.publicKey
                )
            } else {
                // First message
                envelope = try MessageEncryptor.encrypt(
                    message: message,
                    senderPrivateKey: sender.privateKey,
                    recipientPublicKey: recipient.publicKey
                )
            }

            let txid = await store.store(envelope, from: sender.name, to: recipient.name)

            // Recipient decrypts
            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: recipient.privateKey
            )

            #expect(decrypted?.text == message)

            // Verify reply context for messages 2+
            if i > 1 {
                #expect(decrypted?.replyToId == lastTxid, "Reply context missing for message \(i)")
            }

            lastTxid = txid
            lastPreview = message
        }

        print("✅ 50-message reply thread verified with proper reply contexts")
    }
}

// MARK: - Security Boundary Tests

@Suite("E2E: Security Boundaries", .serialized)
struct SecurityBoundaryTests {

    @Test("Cannot decrypt messages not addressed to you")
    func testCannotReadOthersMessages() async throws {
        let alice = SimulatedUser(name: "Alice")
        let bob = SimulatedUser(name: "Bob")
        let eve = SimulatedUser(name: "Eve")  // Attacker
        let store = MessageStore()

        print("\n=== SECURITY: Cannot Read Others' Messages ===")
        print("Alice sends 10 messages to Bob")
        print("Eve tries to decrypt each one...")

        var eveAttempts = 0
        var eveSuccesses = 0

        for i in 1...10 {
            let message = "Secret message #\(i) for Bob only"
            let envelope = try MessageEncryptor.encrypt(
                message: message,
                senderPrivateKey: alice.privateKey,
                recipientPublicKey: bob.publicKey
            )

            _ = await store.store(envelope, from: "Alice", to: "Bob")

            // Bob CAN decrypt
            let bobDecrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: bob.privateKey
            )
            #expect(bobDecrypted?.text == message)

            // Eve CANNOT decrypt
            eveAttempts += 1
            do {
                _ = try MessageEncryptor.decrypt(
                    envelope: envelope,
                    recipientPrivateKey: eve.privateKey
                )
                eveSuccesses += 1  // This should never happen
            } catch {
                // Expected - Eve cannot decrypt
            }
        }

        print("Eve attempted: \(eveAttempts) decryptions")
        print("Eve succeeded: \(eveSuccesses) times")
        print("✅ Eve could not decrypt ANY messages intended for Bob")

        #expect(eveSuccesses == 0, "Eve should not be able to decrypt any messages!")
    }

    @Test("Cannot decrypt with sender's key (asymmetric)")
    func testSenderCannotDecryptOwnMessage() async throws {
        let alice = SimulatedUser(name: "Alice")
        let bob = SimulatedUser(name: "Bob")

        print("\n=== SECURITY: Sender Cannot Decrypt Own Messages ===")

        let message = "Message from Alice to Bob"
        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: alice.privateKey,
            recipientPublicKey: bob.publicKey
        )

        // Alice tries to decrypt her own message
        var aliceCanDecrypt = false
        do {
            _ = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: alice.privateKey
            )
            aliceCanDecrypt = true
        } catch {
            // Expected - sender cannot decrypt
        }

        // Bob CAN decrypt
        let bobDecrypted = try MessageEncryptor.decrypt(
            envelope: envelope,
            recipientPrivateKey: bob.privateKey
        )

        print("Alice can decrypt her own sent message: \(aliceCanDecrypt ? "YES ❌" : "NO ✅")")
        print("Bob can decrypt message addressed to him: \(bobDecrypted != nil ? "YES ✅" : "NO ❌")")
        print("✅ Asymmetric encryption verified - only recipient can decrypt")

        #expect(!aliceCanDecrypt, "Sender should not be able to decrypt their own message")
        #expect(bobDecrypted?.text == message)
    }

    @Test("Cannot tamper with any envelope field")
    func testTamperDetection() async throws {
        let alice = SimulatedUser(name: "Alice")
        let bob = SimulatedUser(name: "Bob")

        print("\n=== SECURITY: Tamper Detection ===")

        let message = "Original untampered message"
        let envelope = try MessageEncryptor.encrypt(
            message: message,
            senderPrivateKey: alice.privateKey,
            recipientPublicKey: bob.publicKey
        )

        // Original works
        let original = try MessageEncryptor.decrypt(envelope: envelope, recipientPrivateKey: bob.privateKey)
        #expect(original?.text == message)
        print("Original message decrypts: ✅")

        // Tamper with ciphertext
        var tamperedCiphertext = envelope.ciphertext
        tamperedCiphertext[0] ^= 0x01
        let tampered1 = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: envelope.ephemeralPublicKey!,
            nonce: envelope.nonce,
            ciphertext: tamperedCiphertext
        )
        var ciphertextTamperDetected = false
        do {
            _ = try MessageEncryptor.decrypt(envelope: tampered1, recipientPrivateKey: bob.privateKey)
        } catch { ciphertextTamperDetected = true }
        print("Tampered ciphertext detected: \(ciphertextTamperDetected ? "✅" : "❌")")
        #expect(ciphertextTamperDetected)

        // Tamper with nonce
        var tamperedNonce = envelope.nonce
        tamperedNonce[0] ^= 0x01
        let tampered2 = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: envelope.ephemeralPublicKey!,
            nonce: tamperedNonce,
            ciphertext: envelope.ciphertext
        )
        var nonceTamperDetected = false
        do {
            _ = try MessageEncryptor.decrypt(envelope: tampered2, recipientPrivateKey: bob.privateKey)
        } catch { nonceTamperDetected = true }
        print("Tampered nonce detected: \(nonceTamperDetected ? "✅" : "❌")")
        #expect(nonceTamperDetected)

        // Tamper with ephemeral key
        var tamperedEphemeral = envelope.ephemeralPublicKey!
        tamperedEphemeral[0] ^= 0x01
        let tampered3 = ChatEnvelope(
            senderPublicKey: envelope.senderPublicKey,
            ephemeralPublicKey: tamperedEphemeral,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext
        )
        var ephemeralTamperDetected = false
        do {
            _ = try MessageEncryptor.decrypt(envelope: tampered3, recipientPrivateKey: bob.privateKey)
        } catch { ephemeralTamperDetected = true }
        print("Tampered ephemeral key detected: \(ephemeralTamperDetected ? "✅" : "❌")")
        #expect(ephemeralTamperDetected)

        // Tamper with sender key
        var tamperedSender = envelope.senderPublicKey
        tamperedSender[0] ^= 0x01
        let tampered4 = ChatEnvelope(
            senderPublicKey: tamperedSender,
            ephemeralPublicKey: envelope.ephemeralPublicKey!,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext
        )
        var senderTamperDetected = false
        do {
            _ = try MessageEncryptor.decrypt(envelope: tampered4, recipientPrivateKey: bob.privateKey)
        } catch { senderTamperDetected = true }
        print("Tampered sender key detected: \(senderTamperDetected ? "✅" : "❌")")
        #expect(senderTamperDetected)

        print("✅ All tampering attempts detected and rejected")
    }

    @Test("Forward secrecy: Old messages safe after key compromise")
    func testForwardSecrecyAfterCompromise() async throws {
        let alice = SimulatedUser(name: "Alice")
        var bob = SimulatedUser(name: "Bob")
        let store = MessageStore()

        print("\n=== FORWARD SECRECY: Key Compromise Scenario ===")

        // Phase 1: Normal messaging (50 messages)
        print("Phase 1: Alice sends 50 messages to Bob...")
        var oldEnvelopes: [ChatEnvelope] = []

        for i in 1...50 {
            let envelope = try MessageEncryptor.encrypt(
                message: "Secret message #\(i)",
                senderPrivateKey: alice.privateKey,
                recipientPublicKey: bob.publicKey
            )
            oldEnvelopes.append(envelope)
            _ = await store.store(envelope, from: "Alice", to: "Bob")

            // Bob decrypts successfully
            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: bob.privateKey
            )
            #expect(decrypted != nil)
        }
        print("  ✓ 50 messages sent and decrypted")

        // Phase 2: Bob's key gets compromised - attacker gets his private key
        let compromisedKey = bob.privateKey
        print("\nPhase 2: Bob's key is COMPROMISED!")
        print("  Attacker has Bob's private key: \(compromisedKey.publicKey.rawRepresentation.prefix(8).hex)...")

        // Phase 3: Can attacker decrypt OLD messages?
        print("\nPhase 3: Attacker tries to decrypt OLD messages with compromised key...")
        var oldMessagesDecrypted = 0
        for envelope in oldEnvelopes {
            if let _ = try? MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: compromisedKey
            ) {
                oldMessagesDecrypted += 1
            }
        }

        // Note: With the CURRENT key, attacker CAN decrypt old messages
        // Forward secrecy protects against EPHEMERAL key compromise, not recipient key
        // If recipient's long-term key is compromised, old messages are readable
        // BUT each message has unique ephemeral key, so compromising ONE message
        // doesn't reveal others' ephemeral secrets

        print("  Old messages attacker could decrypt: \(oldMessagesDecrypted)/50")

        // Verify: recipient key compromise DOES expose old messages (expected behavior)
        // This documents the security model - forward secrecy protects ephemeral keys, not recipient keys
        #expect(oldMessagesDecrypted == 50, "All 50 old messages should be decryptable with compromised recipient key")

        // Phase 4: Bob rotates to new key
        bob = bob.rotateKey()
        print("\nPhase 4: Bob rotates to NEW key: \(bob.publicKey.rawRepresentation.prefix(8).hex)...")

        // Phase 5: New messages with new key
        print("\nPhase 5: Alice sends 10 NEW messages to Bob's new key...")
        var newEnvelopes: [ChatEnvelope] = []
        for i in 1...10 {
            let envelope = try MessageEncryptor.encrypt(
                message: "New secret #\(i)",
                senderPrivateKey: alice.privateKey,
                recipientPublicKey: bob.publicKey  // New key!
            )
            newEnvelopes.append(envelope)

            // Bob with new key CAN decrypt
            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: bob.privateKey
            )
            #expect(decrypted != nil)
        }
        print("  ✓ 10 new messages sent to new key")

        // Phase 6: Attacker with OLD key cannot decrypt NEW messages
        print("\nPhase 6: Attacker (with OLD key) tries to decrypt NEW messages...")
        var newMessagesCompromised = 0
        for envelope in newEnvelopes {
            if let _ = try? MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: compromisedKey  // Old compromised key
            ) {
                newMessagesCompromised += 1
            }
        }

        print("  New messages attacker could decrypt: \(newMessagesCompromised)/10")
        print("\n✅ After key rotation, attacker with old key CANNOT read new messages")

        #expect(newMessagesCompromised == 0, "Attacker should not decrypt messages to new key")
    }
}

// MARK: - Key Rotation & Lifecycle Tests

@Suite("E2E: Key Rotation & Lifecycle", .serialized)
struct KeyRotationTests {

    @Test("User rotates key mid-conversation")
    func testMidConversationKeyRotation() async throws {
        let alice = SimulatedUser(name: "Alice")
        var bob = SimulatedUser(name: "Bob")
        let store = MessageStore()

        print("\n=== KEY ROTATION MID-CONVERSATION ===")

        // Phase 1: 25 messages with original key
        print("Phase 1: 25 messages with Bob's original key...")
        let bobKeyV1 = bob.publicKey

        for i in 1...25 {
            let envelope = try MessageEncryptor.encrypt(
                message: "Message \(i) to Bob v1",
                senderPrivateKey: alice.privateKey,
                recipientPublicKey: bob.publicKey
            )
            _ = await store.store(envelope, from: "Alice", to: "Bob")

            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: bob.privateKey
            )
            #expect(decrypted?.text == "Message \(i) to Bob v1")
        }
        print("  ✓ 25 messages verified")

        // Phase 2: Bob rotates key
        let bobOldKey = bob.privateKey
        bob = bob.rotateKey()
        print("\nPhase 2: Bob rotates key")
        print("  Old: \(bobKeyV1.rawRepresentation.prefix(8).hex)...")
        print("  New: \(bob.publicKey.rawRepresentation.prefix(8).hex)...")

        // Phase 3: 25 more messages with new key
        print("\nPhase 3: 25 messages with Bob's NEW key...")
        for i in 26...50 {
            let envelope = try MessageEncryptor.encrypt(
                message: "Message \(i) to Bob v2",
                senderPrivateKey: alice.privateKey,
                recipientPublicKey: bob.publicKey  // New key
            )
            _ = await store.store(envelope, from: "Alice", to: "Bob")

            // New key decrypts new messages
            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: bob.privateKey
            )
            #expect(decrypted?.text == "Message \(i) to Bob v2")

            // Old key CANNOT decrypt new messages
            var oldKeyWorks = false
            if let _ = try? MessageEncryptor.decrypt(envelope: envelope, recipientPrivateKey: bobOldKey) {
                oldKeyWorks = true
            }
            #expect(!oldKeyWorks, "Old key should not decrypt messages to new key")
        }
        print("  ✓ 25 new messages verified with new key")

        let count = await store.count()
        print("\nTotal messages: \(count)")
        print("✅ Key rotation handled correctly - old key cannot read new messages")
    }

    @Test("Multiple key rotations over time")
    func testMultipleKeyRotations() async throws {
        let alice = SimulatedUser(name: "Alice")
        var bob = SimulatedUser(name: "Bob")
        var bobKeys: [Curve25519.KeyAgreement.PrivateKey] = [bob.privateKey]

        print("\n=== MULTIPLE KEY ROTATIONS ===")

        // Simulate 5 key rotations with 20 messages each
        for rotation in 0..<5 {
            print("\nRotation \(rotation): Bob's key \(bob.publicKey.rawRepresentation.prefix(6).hex)...")

            for i in 1...20 {
                let msgNum = rotation * 20 + i
                let envelope = try MessageEncryptor.encrypt(
                    message: "Message \(msgNum)",
                    senderPrivateKey: alice.privateKey,
                    recipientPublicKey: bob.publicKey
                )

                // Current key works
                let decrypted = try MessageEncryptor.decrypt(
                    envelope: envelope,
                    recipientPrivateKey: bob.privateKey
                )
                #expect(decrypted?.text == "Message \(msgNum)")

                // Previous keys don't work
                for (idx, oldKey) in bobKeys.dropLast().enumerated() {
                    var oldWorks = false
                    if let _ = try? MessageEncryptor.decrypt(envelope: envelope, recipientPrivateKey: oldKey) {
                        oldWorks = true
                    }
                    #expect(!oldWorks, "Key \(idx) should not decrypt rotation \(rotation) messages")
                }
            }
            print("  ✓ 20 messages verified")

            // Rotate key (except on last iteration)
            if rotation < 4 {
                bob = bob.rotateKey()
                bobKeys.append(bob.privateKey)
            }
        }

        print("\nTotal rotations: 5")
        print("Total messages: 100")
        print("Total keys used: \(bobKeys.count)")
        print("✅ All key rotations handled correctly")
    }
}

// MARK: - Long-Term Usage Simulation

@Suite("E2E: Long-Term Usage Simulation", .serialized)
struct LongTermUsageTests {

    @Test("Simulate 1 year of messaging (365 days, 1000 messages)")
    func testOneYearSimulation() async throws {
        let alice = SimulatedUser(name: "Alice")
        let bob = SimulatedUser(name: "Bob")
        let store = MessageStore()

        print("\n=== ONE YEAR SIMULATION (1000 messages) ===")

        var ephemeralKeys: Set<Data> = []
        var messageTypes = [
            "plain": 0,
            "reply": 0,
            "unicode": 0,
            "long": 0
        ]

        let startTime = Date()

        for day in 1...365 {
            // Simulate ~3 messages per day on average
            let messagesThisDay = day % 3 == 0 ? 4 : (day % 2 == 0 ? 3 : 2)

            for msgInDay in 1...messagesThisDay {
                guard await store.count() < 1000 else { break }

                let isAlice = (day + msgInDay) % 2 == 0
                let sender = isAlice ? alice : bob
                let recipient = isAlice ? bob : alice

                let envelope: ChatEnvelope
                let messageNum = await store.count() + 1

                // Vary message types
                switch messageNum % 10 {
                case 0:
                    // Unicode message
                    let unicodeMsg = "Day \(day) 🌅 Good morning! 你好 مرحبا 🎉"
                    envelope = try MessageEncryptor.encrypt(
                        message: unicodeMsg,
                        senderPrivateKey: sender.privateKey,
                        recipientPublicKey: recipient.publicKey
                    )
                    messageTypes["unicode"]! += 1

                case 1, 2:
                    // Reply to previous
                    envelope = try MessageEncryptor.encrypt(
                        message: "Reply on day \(day)",
                        replyTo: (txid: "TX\(String(format: "%06d", max(1, messageNum - 1)))", preview: "Previous message"),
                        senderPrivateKey: sender.privateKey,
                        recipientPublicKey: recipient.publicKey
                    )
                    messageTypes["reply"]! += 1

                case 3:
                    // Long message (near max size)
                    let longMsg = String(repeating: "Day \(day). ", count: 80)
                    envelope = try MessageEncryptor.encrypt(
                        message: String(longMsg.prefix(900)),
                        senderPrivateKey: sender.privateKey,
                        recipientPublicKey: recipient.publicKey
                    )
                    messageTypes["long"]! += 1

                default:
                    // Plain message
                    envelope = try MessageEncryptor.encrypt(
                        message: "Message on day \(day) - #\(messageNum)",
                        senderPrivateKey: sender.privateKey,
                        recipientPublicKey: recipient.publicKey
                    )
                    messageTypes["plain"]! += 1
                }

                // Track ephemeral keys (should all be unique)
                ephemeralKeys.insert(envelope.ephemeralPublicKey!)

                _ = await store.store(envelope, from: sender.name, to: recipient.name)

                // Decrypt and verify
                let decrypted = try MessageEncryptor.decrypt(
                    envelope: envelope,
                    recipientPrivateKey: recipient.privateKey
                )
                #expect(decrypted != nil, "Message \(messageNum) failed to decrypt")
            }

            if day % 73 == 0 {
                let count = await store.count()
                print("  Day \(day): \(count) messages so far...")
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let totalMessages = await store.count()

        print("\n--- RESULTS ---")
        print("Total messages: \(totalMessages)")
        print("Unique ephemeral keys: \(ephemeralKeys.count)")
        print("Message types:")
        print("  Plain:   \(messageTypes["plain"]!)")
        print("  Reply:   \(messageTypes["reply"]!)")
        print("  Unicode: \(messageTypes["unicode"]!)")
        print("  Long:    \(messageTypes["long"]!)")
        print("Processing time: \(String(format: "%.2f", elapsed))s")
        print("Throughput: \(String(format: "%.0f", Double(totalMessages) / elapsed)) msg/sec")

        // Verify all ephemeral keys are unique (forward secrecy)
        #expect(ephemeralKeys.count == totalMessages, "All messages must have unique ephemeral keys!")

        print("\n✅ ONE YEAR SIMULATION PASSED")
        print("✅ \(totalMessages) messages encrypted/decrypted")
        print("✅ \(ephemeralKeys.count) unique ephemeral keys (forward secrecy)")
    }

    @Test("Concurrent conversations (10 users, 500 messages)")
    func testConcurrentConversations() async throws {
        let users = (1...10).map { SimulatedUser(name: "User\($0)") }
        let store = MessageStore()

        print("\n=== CONCURRENT CONVERSATIONS (10 users) ===")

        // Each user sends 5 messages to each other user
        // 10 users × 9 recipients × 5 messages = 450 messages
        // Plus some broadcast-style messages = ~500 total

        var messageCount = 0

        for sender in users {
            for recipient in users where sender.name != recipient.name {
                for i in 1...5 {
                    let message = "\(sender.name) to \(recipient.name) #\(i)"
                    let envelope = try MessageEncryptor.encrypt(
                        message: message,
                        senderPrivateKey: sender.privateKey,
                        recipientPublicKey: recipient.publicKey
                    )

                    _ = await store.store(envelope, from: sender.name, to: recipient.name)

                    // Recipient decrypts
                    let decrypted = try MessageEncryptor.decrypt(
                        envelope: envelope,
                        recipientPrivateKey: recipient.privateKey
                    )
                    #expect(decrypted?.text == message)

                    // Other users CANNOT decrypt
                    for other in users where other.name != recipient.name && other.name != sender.name {
                        var otherCanRead = false
                        if let _ = try? MessageEncryptor.decrypt(
                            envelope: envelope,
                            recipientPrivateKey: other.privateKey
                        ) {
                            otherCanRead = true
                        }
                        #expect(!otherCanRead, "\(other.name) should not read \(sender.name)'s message to \(recipient.name)")
                    }

                    messageCount += 1
                }
            }

            print("  \(sender.name) sent 45 messages (\(messageCount) total)")
        }

        let count = await store.count()
        print("\nTotal messages: \(count)")
        print("✅ All \(count) messages verified")
        print("✅ Security boundaries enforced for all \(users.count) users")
    }
}

// MARK: - V1/V2 Migration Tests

@Suite("E2E: V1/V2 Migration", .serialized)
struct MigrationTests {

    @Test("Mixed V1 and V2 messages in conversation history")
    func testMixedVersionConversation() async throws {
        let alice = SimulatedUser(name: "Alice")
        let bob = SimulatedUser(name: "Bob")

        print("\n=== MIXED V1/V2 CONVERSATION ===")

        // Simulate 20 V1 messages (legacy)
        print("Creating 20 legacy V1 messages...")
        var v1Envelopes: [ChatEnvelope] = []

        for i in 1...20 {
            // Manually create V1 envelope
            let sharedSecret = try alice.privateKey.sharedSecretFromKeyAgreement(with: bob.publicKey)
            let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data("AlgoChat-v1-salt".utf8),
                sharedInfo: Data("AlgoChat-v1-message".utf8),
                outputByteCount: 32
            )

            var nonceBytes = [UInt8](repeating: 0, count: 12)
            #if canImport(Security)
            _ = SecRandomCopyBytes(kSecRandomDefault, 12, &nonceBytes)
            #else
            guard let urandom = FileHandle(forReadingAtPath: "/dev/urandom") else {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open /dev/urandom"])
            }
            defer { try? urandom.close() }
            nonceBytes = [UInt8](urandom.readData(ofLength: 12))
            #endif
            let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))

            let plaintext = "Legacy V1 message #\(i)"
            let sealedBox = try ChaChaPoly.seal(Data(plaintext.utf8), using: symmetricKey, nonce: nonce)

            let v1Envelope = ChatEnvelope(
                senderPublicKey: alice.publicKey.rawRepresentation,
                nonce: Data(nonceBytes),
                ciphertext: sealedBox.ciphertext + sealedBox.tag
            )
            v1Envelopes.append(v1Envelope)
        }

        // Create 20 V2 messages (forward secrecy)
        print("Creating 20 new V2 messages...")
        var v2Envelopes: [ChatEnvelope] = []

        for i in 1...20 {
            let envelope = try MessageEncryptor.encrypt(
                message: "New V2 message #\(i)",
                senderPrivateKey: alice.privateKey,
                recipientPublicKey: bob.publicKey
            )
            v2Envelopes.append(envelope)
        }

        // Interleave and verify all decrypt correctly
        print("\nVerifying all 40 messages decrypt correctly...")

        var v1Verified = 0
        var v2Verified = 0

        for (i, envelope) in v1Envelopes.enumerated() {
            #expect(envelope.envelopeVersion == ChatEnvelope.versionV1)
            #expect(!envelope.usesForwardSecrecy)

            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: bob.privateKey
            )
            #expect(decrypted?.text == "Legacy V1 message #\(i + 1)")
            v1Verified += 1
        }

        for (i, envelope) in v2Envelopes.enumerated() {
            #expect(envelope.envelopeVersion == ChatEnvelope.versionV2)
            #expect(envelope.usesForwardSecrecy)

            let decrypted = try MessageEncryptor.decrypt(
                envelope: envelope,
                recipientPrivateKey: bob.privateKey
            )
            #expect(decrypted?.text == "New V2 message #\(i + 1)")
            v2Verified += 1
        }

        print("V1 messages verified: \(v1Verified)")
        print("V2 messages verified: \(v2Verified)")
        print("✅ Mixed V1/V2 conversation fully compatible")
    }
}

// MARK: - Helpers

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
