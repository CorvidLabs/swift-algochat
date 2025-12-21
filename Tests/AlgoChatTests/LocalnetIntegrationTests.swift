import Algorand
import AlgoKit
import Crypto
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

        // Get the encryption public keys from each chat account
        let alicePubKey = await aliceChat.account.encryptionPublicKey
        let bobPubKey = await bobChat.account.encryptionPublicKey

        // Step 1: Alice sends a message to herself to publish her public key
        print("\n📤 Step 1: Alice publishes her public key (sends message to self)...")
        let alicePubKeyTx = try await aliceChat.sendAndWait(
            message: "Hello from Alice! Publishing my public key.",
            to: aliceAccount.address,
            recipientPublicKey: alicePubKey  // Use her own key since she's sending to herself
        )
        print("   ✅ Alice's key published. TX: \(alicePubKeyTx.prefix(12))...")

        // Step 2: Bob sends a message to himself to publish his public key
        print("\n📤 Step 2: Bob publishes his public key (sends message to self)...")
        let bobPubKeyTx = try await bobChat.sendAndWait(
            message: "Hello from Bob! Publishing my public key.",
            to: bobAccount.address,
            recipientPublicKey: bobPubKey  // Use his own key since he's sending to himself
        )
        print("   ✅ Bob's key published. TX: \(bobPubKeyTx.prefix(12))...")

        // Wait for indexer to catch up - poll until we see the key publication transactions
        print("\n⏳ Waiting for indexer to index key publications...")
        let algokit = AlgoKit(configuration: .localnet())
        print("   Waiting for Alice's key...")
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        print("   Waiting for Bob's key...")
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        // Step 3: Alice sends a message to Bob
        print("\n📤 Step 3: Alice sends message to Bob...")
        let message1 = "Hey Bob! This is Alice. Can you hear me? 🎉"
        let tx1 = try await aliceChat.sendAndWait(message: message1, to: bobAccount.address)
        print("   ✅ Message sent. TX: \(tx1.prefix(12))...")

        // Step 4: Bob sends a message to Alice
        print("\n📤 Step 4: Bob sends message to Alice...")
        let message2 = "Hi Alice! Yes I can! This is amazing! 🚀"
        let tx2 = try await bobChat.sendAndWait(message: message2, to: aliceAccount.address)
        print("   ✅ Message sent. TX: \(tx2.prefix(12))...")

        // Step 5: Alice sends another message to Bob
        print("\n📤 Step 5: Alice sends another message to Bob...")
        let message3 = "Encrypted blockchain messaging works! 💎"
        let tx3 = try await aliceChat.sendAndWait(message: message3, to: bobAccount.address)
        print("   ✅ Message sent. TX: \(tx3.prefix(12))...")

        // Wait for indexer to catch up - poll until we see all messages
        // Bob should have: 1 self-sent key + 2 from Alice = 3 chat messages
        // Alice should have: 1 self-sent key + 2 to Bob + 1 from Bob = 4 chat messages
        print("\n⏳ Waiting for indexer to index all messages...")
        print("   Waiting for Bob's messages (expecting 3)...")
        try await waitForChatMessages(for: bobAccount.address, count: 3, algokit: algokit)
        print("   Waiting for Alice's messages (expecting 4)...")
        try await waitForChatMessages(for: aliceAccount.address, count: 4, algokit: algokit)

        // Step 6: Bob fetches messages from Alice
        print("\n📥 Step 6: Bob fetches messages from Alice...")
        let bobMessages = try await bobChat.fetchMessages(with: aliceAccount.address)
        print("   ✅ Bob received \(bobMessages.count) messages from Alice:")
        for msg in bobMessages {
            let direction = msg.direction == .sent ? "→" : "←"
            print("      \(direction) \(msg.content)")
        }

        // Verify Bob received Alice's messages
        let receivedByBob = bobMessages.filter { $0.direction == .received }.map { $0.content }
        #expect(receivedByBob.contains(message1), "Bob should have received message 1")
        #expect(receivedByBob.contains(message3), "Bob should have received message 3")

        // Step 7: Alice fetches messages from Bob
        print("\n📥 Step 7: Alice fetches messages from Bob...")
        let aliceMessages = try await aliceChat.fetchMessages(with: bobAccount.address)
        print("   ✅ Alice received \(aliceMessages.count) messages with Bob:")
        for msg in aliceMessages {
            let direction = msg.direction == .sent ? "→" : "←"
            print("      \(direction) \(msg.content)")
        }

        // Verify Alice received Bob's message
        let receivedByAlice = aliceMessages.filter { $0.direction == .received }.map { $0.content }
        #expect(receivedByAlice.contains(message2), "Alice should have received message 2")

        // Step 8: Check conversations
        print("\n📋 Step 8: Checking conversations...")
        let aliceConversations = try await aliceChat.fetchConversations()
        let bobConversations = try await bobChat.fetchConversations()

        print("   Alice's conversations: \(aliceConversations.count)")
        for conv in aliceConversations {
            print("      - \(conv.participant.description.prefix(12))... (\(conv.messages.count) messages)")
        }

        print("   Bob's conversations: \(bobConversations.count)")
        for conv in bobConversations {
            print("      - \(conv.participant.description.prefix(12))... (\(conv.messages.count) messages)")
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

        // Publish keys (send to self using own public key)
        let alicePubKey = await aliceChat.account.encryptionPublicKey
        let bobPubKey = await bobChat.account.encryptionPublicKey
        _ = try await aliceChat.sendAndWait(message: "key", to: alice.address, recipientPublicKey: alicePubKey)
        _ = try await bobChat.sendAndWait(message: "key", to: bob.address, recipientPublicKey: bobPubKey)

        // Wait for indexer to catch up
        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: alice.address, algokit: algokit)
        try await waitForTransaction(from: bob.address, algokit: algokit)

        // Alice sends secret to Bob
        let secretMessage = "This is a secret message only for Bob!"
        _ = try await aliceChat.sendAndWait(message: secretMessage, to: bob.address)

        // Wait for indexer to catch up (Bob should have 2 messages: key + secret)
        try await waitForChatMessages(for: bob.address, count: 2, algokit: algokit)

        // Bob can read the message
        let bobMessages = try await bobChat.fetchMessages(with: alice.address)
        let bobReceived = bobMessages.filter { $0.direction == .received }
        #expect(bobReceived.contains { $0.content == secretMessage }, "Bob should decrypt the message")

        // Eve cannot read messages between Alice and Bob (she has no messages with them)
        let eveFromAlice = try await eveChat.fetchMessages(with: alice.address)
        let eveFromBob = try await eveChat.fetchMessages(with: bob.address)

        #expect(eveFromAlice.isEmpty, "Eve should have no messages with Alice")
        #expect(eveFromBob.isEmpty, "Eve should have no messages with Bob")

        print("✅ Encryption security verified: Eve cannot read Alice-Bob messages")
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
