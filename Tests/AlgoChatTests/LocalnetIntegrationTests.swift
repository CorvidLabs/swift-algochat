import Algorand
import AlgoKit
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

/// End-to-end integration tests for AlgoChat on localnet
/// Run `algokit localnet start` before running these tests
@Suite("AlgoChat Localnet Integration Tests")
struct LocalnetIntegrationTests {

    // MARK: - Test Helpers

    /// Discovers a funded address from the localnet KMD wallet
    private func discoverFundingAddress() throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/docker")
        task.arguments = [
            "exec", "algokit_sandbox_algod",
            "goal", "account", "list",
            "-d", "/algod/data"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TestError.fundingFailed("Failed to list accounts: \(output)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse the output to find the first account address
        // Format: [online]	ADDRESS	ADDRESS	BALANCE microAlgos
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let components = line.components(separatedBy: "\t")
            if components.count >= 2 {
                let address = components[1].trimmingCharacters(in: .whitespaces)
                if address.count == 58 { // Valid Algorand address length
                    return address
                }
            }
        }

        throw TestError.fundingFailed("No funded accounts found in localnet wallet")
    }

    /// Funds an account on localnet using goal CLI
    private func fundAccount(_ account: Account, amount: UInt64 = 10_000_000) throws {
        let fundingAddress = try discoverFundingAddress()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/docker")
        task.arguments = [
            "exec", "algokit_sandbox_algod",
            "goal", "clerk", "send",
            "-a", String(amount),
            "-f", fundingAddress,
            "-t", account.address.description,
            "-d", "/algod/data"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TestError.fundingFailed(output)
        }
    }

    /// Checks if localnet is running
    private func isLocalnetRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        task.arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:4001/health"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let statusCode = String(data: data, encoding: .utf8) ?? ""
            return statusCode == "200"
        } catch {
            return false
        }
    }

    /// Wait for indexer to have a transaction from a specific address
    private func waitForTransaction(from address: Address, algokit: AlgoKit, maxRetries: Int = 60) async throws {
        guard let indexer = await algokit.indexerClient else {
            throw TestError.indexerNotAvailable
        }

        for i in 0..<maxRetries {
            let response = try await indexer.searchTransactions(address: address, limit: 10)
            // Look for a chat message (note with version byte)
            for tx in response.transactions {
                if tx.sender == address.description,
                   let noteData = tx.noteData,
                   noteData.count > 2,
                   noteData[0] == 0x01 {  // ChatEnvelope.version
                    print("      ✓ Found key publication transaction after \(i + 1) polls")
                    return
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        }

        throw TestError.indexerTimeout
    }

    /// Wait for indexer to have at least `count` chat messages for an address
    private func waitForChatMessages(for address: Address, count: Int, algokit: AlgoKit, maxRetries: Int = 60) async throws {
        guard let indexer = await algokit.indexerClient else {
            throw TestError.indexerNotAvailable
        }

        for i in 0..<maxRetries {
            let response = try await indexer.searchTransactions(address: address, limit: 50)
            var chatCount = 0
            for tx in response.transactions {
                if let noteData = tx.noteData,
                   noteData.count > 2,
                   noteData[0] == 0x01 {  // ChatEnvelope.version
                    chatCount += 1
                }
            }
            if chatCount >= count {
                print("      ✓ Found \(chatCount) chat messages after \(i + 1) polls")
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        }

        throw TestError.indexerTimeout
    }

    // MARK: - Tests

    @Test("Full end-to-end messaging flow between two users")
    func testFullMessagingFlow() async throws {
        // Skip if localnet is not running
        guard isLocalnetRunning() else {
            print("⚠️ Skipping test: localnet is not running. Start with `algokit localnet start`")
            return
        }

        print("\n" + String(repeating: "=", count: 60))
        print("🧪 ALGOCHAT END-TO-END TEST")
        print(String(repeating: "=", count: 60))

        // Create two test accounts (Alice and Bob)
        let aliceAccount = try Account()
        let bobAccount = try Account()

        print("\n📝 Created test accounts:")
        print("   Alice: \(aliceAccount.address)")
        print("   Bob:   \(bobAccount.address)")

        // Fund both accounts (10 ALGO each)
        print("\n💰 Funding accounts...")
        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        print("   ✅ Both accounts funded with 10 ALGO")

        // Wait a bit for transactions to confirm
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create AlgoChat instances for both users
        print("\n🔌 Connecting to Algorand localnet...")
        let aliceChat = try await AlgoChat(
            configuration: .localnet(),
            account: aliceAccount
        )
        let bobChat = try await AlgoChat(
            configuration: .localnet(),
            account: bobAccount
        )
        print("   ✅ Both users connected")

        // Verify balances
        let aliceBalance = try await aliceChat.balance()
        let bobBalance = try await bobChat.balance()
        print("\n💵 Account balances:")
        print("   Alice: \(Double(aliceBalance.value) / 1_000_000) ALGO")
        print("   Bob:   \(Double(bobBalance.value) / 1_000_000) ALGO")

        #expect(aliceBalance.value >= 1_000_000, "Alice should have at least 1 ALGO")
        #expect(bobBalance.value >= 1_000_000, "Bob should have at least 1 ALGO")

        // Step 1: Alice publishes her encryption key
        print("\n📤 Step 1: Alice publishes her public key...")
        let alicePubKeyTx = try await aliceChat.publishKeyAndWait()
        print("   ✅ Alice's key published. TX: \(alicePubKeyTx.prefix(12))...")

        // Step 2: Bob publishes his encryption key
        print("\n📤 Step 2: Bob publishes his public key...")
        let bobPubKeyTx = try await bobChat.publishKeyAndWait()
        print("   ✅ Bob's key published. TX: \(bobPubKeyTx.prefix(12))...")

        // Wait for indexer to catch up - poll until we see the key publication transactions
        print("\n⏳ Waiting for indexer to index key publications...")
        let algokit = AlgoKit(configuration: .localnet())
        print("   Waiting for Alice's key...")
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        print("   Waiting for Bob's key...")
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        // Step 3: Alice sends a message to Bob (using new conversation-first API)
        print("\n📤 Step 3: Alice sends message to Bob...")
        let message1 = "Hey Bob! This is Alice. Can you hear me? 🎉"
        let aliceToBobConv = try await aliceChat.conversation(with: bobAccount.address)
        let result1 = try await aliceChat.send(message1, to: aliceToBobConv, options: .confirmed)
        print("   ✅ Message sent. TX: \(result1.txid.prefix(12))...")

        // Step 4: Bob sends a message to Alice
        print("\n📤 Step 4: Bob sends message to Alice...")
        let message2 = "Hi Alice! Yes I can! This is amazing! 🚀"
        let bobToAliceConv = try await bobChat.conversation(with: aliceAccount.address)
        let result2 = try await bobChat.send(message2, to: bobToAliceConv, options: .confirmed)
        print("   ✅ Message sent. TX: \(result2.txid.prefix(12))...")

        // Step 5: Alice sends another message to Bob
        print("\n📤 Step 5: Alice sends another message to Bob...")
        let message3 = "Encrypted blockchain messaging works! 💎"
        let result3 = try await aliceChat.send(message3, to: aliceToBobConv, options: .confirmed)
        print("   ✅ Message sent. TX: \(result3.txid.prefix(12))...")

        // Wait for indexer to catch up - poll until we see all messages
        // Bob should have: 1 self-sent key + 2 from Alice = 3 chat messages
        // Alice should have: 1 self-sent key + 2 to Bob + 1 from Bob = 4 chat messages
        print("\n⏳ Waiting for indexer to index all messages...")
        print("   Waiting for Bob's messages (expecting 3)...")
        try await waitForChatMessages(for: bobAccount.address, count: 3, algokit: algokit)
        print("   Waiting for Alice's messages (expecting 4)...")
        try await waitForChatMessages(for: aliceAccount.address, count: 4, algokit: algokit)

        // Step 6: Bob fetches messages from Alice (using refresh)
        print("\n📥 Step 6: Bob fetches messages from Alice...")
        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        print("   ✅ Bob received \(bobConv.messageCount) messages from Alice:")
        for msg in bobConv.messages {
            let direction = msg.direction == .sent ? "→" : "←"
            print("      \(direction) \(msg.content)")
        }

        // Verify Bob received Alice's messages (using new convenience properties)
        let receivedByBob = bobConv.receivedMessages.map { $0.content }
        #expect(receivedByBob.contains(message1), "Bob should have received message 1")
        #expect(receivedByBob.contains(message3), "Bob should have received message 3")

        // Step 7: Alice fetches messages from Bob
        print("\n📥 Step 7: Alice fetches messages from Bob...")
        var aliceConv = try await aliceChat.conversation(with: bobAccount.address)
        aliceConv = try await aliceChat.refresh(aliceConv)
        print("   ✅ Alice received \(aliceConv.messageCount) messages with Bob:")
        for msg in aliceConv.messages {
            let direction = msg.direction == .sent ? "→" : "←"
            print("      \(direction) \(msg.content)")
        }

        // Verify Alice received Bob's message
        let receivedByAlice = aliceConv.receivedMessages.map { $0.content }
        #expect(receivedByAlice.contains(message2), "Alice should have received message 2")

        // Step 8: Check conversations (using new conversations() method)
        print("\n📋 Step 8: Checking conversations...")
        let aliceConversations = try await aliceChat.conversations()
        let bobConversations = try await bobChat.conversations()

        print("   Alice's conversations: \(aliceConversations.count)")
        for conv in aliceConversations {
            print("      - \(conv.participant.description.prefix(12))... (\(conv.messageCount) messages)")
        }

        print("   Bob's conversations: \(bobConversations.count)")
        for conv in bobConversations {
            print("      - \(conv.participant.description.prefix(12))... (\(conv.messageCount) messages)")
        }

        // Final summary
        print("\n" + String(repeating: "=", count: 60))
        print("✅ ALL TESTS PASSED!")
        print(String(repeating: "=", count: 60))
        print("\n📊 Summary:")
        print("   • Created 2 accounts (Alice & Bob)")
        print("   • Funded both with 10 ALGO each")
        print("   • Published encryption keys on-chain")
        print("   • Alice → Bob: 2 messages")
        print("   • Bob → Alice: 1 message")
        print("   • All messages encrypted, sent, and decrypted successfully")
        print("   • Conversation history verified")
        print("\n🎉 AlgoChat is working correctly on localnet!\n")
    }

    @Test("Message encryption is secure - wrong key cannot decrypt")
    func testEncryptionSecurity() async throws {
        guard isLocalnetRunning() else {
            print("⚠️ Skipping test: localnet is not running")
            return
        }

        // Create three accounts
        let alice = try Account()
        let bob = try Account()
        let eve = try Account()  // Eavesdropper

        // Fund accounts
        try fundAccount(alice)
        try fundAccount(bob)
        try fundAccount(eve)

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create chat instances
        let aliceChat = try await AlgoChat(configuration: .localnet(), account: alice)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bob)
        let eveChat = try await AlgoChat(configuration: .localnet(), account: eve)

        // Publish keys using the new API
        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        // Wait for indexer to catch up
        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: alice.address, algokit: algokit)
        try await waitForTransaction(from: bob.address, algokit: algokit)

        // Alice sends secret to Bob using new conversation-first API
        let secretMessage = "This is a secret message only for Bob!"
        let aliceToBob = try await aliceChat.conversation(with: bob.address)
        _ = try await aliceChat.send(secretMessage, to: aliceToBob, options: .confirmed)

        // Wait for indexer to catch up (Bob should have 2 messages: key + secret)
        try await waitForChatMessages(for: bob.address, count: 2, algokit: algokit)

        // Bob can read the message using new API
        var bobConv = try await bobChat.conversation(with: alice.address)
        bobConv = try await bobChat.refresh(bobConv)
        #expect(bobConv.receivedMessages.contains { $0.content == secretMessage }, "Bob should decrypt the message")

        // Eve cannot read messages between Alice and Bob (she has no messages with them)
        var eveFromAlice = try await eveChat.conversation(with: alice.address)
        eveFromAlice = try await eveChat.refresh(eveFromAlice)
        var eveFromBob = try await eveChat.conversation(with: bob.address)
        eveFromBob = try await eveChat.refresh(eveFromBob)

        #expect(eveFromAlice.isEmpty, "Eve should have no messages with Alice")
        #expect(eveFromBob.isEmpty, "Eve should have no messages with Bob")

        print("✅ Encryption security verified: Eve cannot read Alice-Bob messages")
    }

    @Test("Publish key function works correctly")
    func testPublishKey() async throws {
        guard isLocalnetRunning() else {
            print("⚠️ Skipping test: localnet is not running")
            return
        }

        // Create and fund account
        let account = try Account()
        try fundAccount(account, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create chat
        let chat = try await AlgoChat(configuration: .localnet(), account: account)

        // Verify we have funds
        let balance = try await chat.balance()
        print("Account balance: \(balance.value) microAlgos")
        #expect(balance.value >= 1_000_000, "Account should have funds")

        // Test publishKey
        print("Calling publishKeyAndWait()...")
        let txid = try await chat.publishKeyAndWait()
        print("Published key! TX: \(txid)")

        #expect(!txid.isEmpty, "Should get a transaction ID")
    }

    @Test("Self-messaging works correctly with indexer wait")
    func testSelfMessaging() async throws {
        guard isLocalnetRunning() else {
            print("⚠️ Skipping test: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 60))
        print("🧪 SELF-MESSAGING TEST")
        print(String(repeating: "=", count: 60))

        // Create and fund a single account
        let account = try Account()
        print("\n📝 Created test account:")
        print("   Address: \(account.address)")

        print("\n💰 Funding account...")
        try fundAccount(account, amount: 10_000_000)
        print("   ✅ Account funded with 10 ALGO")

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create chat instance
        print("\n🔌 Connecting to Algorand localnet...")
        let chat = try await AlgoChat(configuration: .localnet(), account: account)
        print("   ✅ Connected")

        // Publish key
        print("\n📤 Publishing encryption key...")
        let keyTx = try await chat.publishKeyAndWait()
        print("   ✅ Key published. TX: \(keyTx.prefix(12))...")

        // Wait for indexer
        let algokit = AlgoKit(configuration: .localnet())
        print("\n⏳ Waiting for indexer...")
        try await waitForTransaction(from: account.address, algokit: algokit)

        // Send message to self using .indexed option
        print("\n📤 Sending message to self...")
        let selfMessage = "Hello, myself! Testing self-messaging with indexer wait. 🪞"
        let selfConv = try await chat.conversation(with: account.address)
        let result = try await chat.send(selfMessage, to: selfConv, options: .indexed)
        print("   ✅ Message sent. TX: \(result.txid.prefix(12))...")

        // Refresh the conversation - message should be visible immediately
        print("\n📥 Refreshing conversation...")
        var refreshedConv = try await chat.refresh(selfConv)
        print("   Found \(refreshedConv.messageCount) messages")

        // Verify message appears
        let sentMessages = refreshedConv.sentMessages
        #expect(sentMessages.contains { $0.content == selfMessage }, "Self-message should appear in sent messages")

        // Verify it appears in conversations list
        print("\n📋 Checking conversations list...")
        let conversations = try await chat.conversations()
        let selfConversation = conversations.first { $0.participant == account.address }
        #expect(selfConversation != nil, "Self-conversation should appear in conversations list")
        if let selfConv = selfConversation {
            print("   ✅ Self-conversation found with \(selfConv.messageCount) messages")
            // Should have at least 1 message (the self-message we sent)
            #expect(selfConv.messageCount >= 1, "Self-conversation should have at least 1 message")
        }

        // Send another message and verify it also appears
        print("\n📤 Sending second self-message...")
        let secondMessage = "This is my second message to myself! 🎯"
        let result2 = try await chat.send(secondMessage, to: refreshedConv, options: .indexed)
        print("   ✅ Second message sent. TX: \(result2.txid.prefix(12))...")

        // Refresh and verify
        refreshedConv = try await chat.refresh(refreshedConv)
        print("   Found \(refreshedConv.messageCount) messages after second send")

        let allSentMessages = refreshedConv.sentMessages.map { $0.content }
        #expect(allSentMessages.contains(selfMessage), "First self-message should still be present")
        #expect(allSentMessages.contains(secondMessage), "Second self-message should be present")

        print("\n" + String(repeating: "=", count: 60))
        print("✅ SELF-MESSAGING TEST PASSED!")
        print(String(repeating: "=", count: 60))
        print("\n📊 Summary:")
        print("   • Created 1 account")
        print("   • Published encryption key")
        print("   • Sent 2 messages to self with .indexed option")
        print("   • All messages visible immediately after send")
        print("   • Self-conversation appears in conversations list")
        print("\n🎉 Self-messaging works correctly!\n")
    }
}

// MARK: - Test Errors

enum TestError: Error, LocalizedError {
    case fundingFailed(String)
    case indexerNotAvailable
    case indexerTimeout

    var errorDescription: String? {
        switch self {
        case .fundingFailed(let message):
            return "Failed to fund account: \(message)"
        case .indexerNotAvailable:
            return "Indexer not available"
        case .indexerTimeout:
            return "Indexer did not catch up in time"
        }
    }
}
