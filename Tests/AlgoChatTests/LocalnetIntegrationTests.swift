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

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let components = line.components(separatedBy: "\t")
            if components.count >= 2 {
                let address = components[1].trimmingCharacters(in: .whitespaces)
                if address.count == 58 {
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
            for tx in response.transactions {
                if tx.sender == address.description,
                   let noteData = tx.noteData,
                   noteData.count > 2,
                   noteData[0] == 0x01 {
                    print("      [indexer] Found key publication after \(i + 1) polls")
                    return
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
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
                   noteData[0] == 0x01 {
                    chatCount += 1
                }
            }
            if chatCount >= count {
                print("      [indexer] Found \(chatCount)/\(count) chat messages after \(i + 1) polls")
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw TestError.indexerTimeout
    }

    // MARK: - Logging Helpers

    /// Logs a transaction with full detail
    private func logTx(
        label: String,
        txid: String,
        from sender: String,
        to recipient: String,
        plaintext: String,
        protocol proto: String = "standard",
        amount: String = "0.001 ALGO"
    ) {
        print("   [TX] \(label)")
        print("         txid:      \(txid)")
        print("         sender:    \(sender)")
        print("         recipient: \(recipient)")
        print("         plaintext: \"\(plaintext)\"")
        print("         protocol:  \(proto)")
        print("         amount:    \(amount)")
    }

    /// Logs a verification check with expected vs actual
    @discardableResult
    private func verify(
        _ description: String,
        expected: String,
        actual: String,
        pass: Bool
    ) -> Bool {
        let status = pass ? "PASS" : "FAIL"
        print("   [VERIFY] \(description)")
        print("            expected: \(expected)")
        print("            actual:   \(actual)")
        print("            result:   \(status)")
        return pass
    }

    /// Logs all messages in a conversation
    private func logConversation(_ conv: Conversation, owner: String) {
        print("   [CONVERSATION] \(owner) <-> \(conv.participant)")
        print("                  total messages: \(conv.messageCount)")
        print("                  sent: \(conv.sentMessages.count), received: \(conv.receivedMessages.count)")
        for msg in conv.messages {
            let dir = msg.direction == .sent ? "SENT >>>" : "<<< RECV"
            let proto = msg.protocolMode?.rawValue ?? "unknown"
            let reply = msg.isReply ? " [reply to \(msg.replyContext?.messageId.prefix(12) ?? "?")...]" : ""
            print("                  \(dir) [\(proto)] \"\(msg.content)\"\(reply)")
            print("                        txid=\(msg.id) round=\(msg.confirmedRound)")
        }
    }

    // MARK: - Tests

    @Test("Full end-to-end messaging flow between two users")
    func testFullMessagingFlow() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 1: Full end-to-end messaging flow between two users")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()

        print("\n   [SETUP] Created accounts:")
        print("           Alice: \(aliceAccount.address)")
        print("           Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        print("   [SETUP] Funded both with 10 ALGO")

        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)

        let aliceBalance = try await aliceChat.balance()
        let bobBalance = try await bobChat.balance()

        verify("Alice balance >= 1 ALGO",
            expected: ">= 1000000 microAlgos",
            actual: "\(aliceBalance.value) microAlgos",
            pass: aliceBalance.value >= 1_000_000)
        #expect(aliceBalance.value >= 1_000_000)

        verify("Bob balance >= 1 ALGO",
            expected: ">= 1000000 microAlgos",
            actual: "\(bobBalance.value) microAlgos",
            pass: bobBalance.value >= 1_000_000)
        #expect(bobBalance.value >= 1_000_000)

        let alicePubKeyTx = try await aliceChat.publishKeyAndWait()
        logTx(label: "Alice publishes key", txid: alicePubKeyTx,
            from: aliceAccount.address.description, to: aliceAccount.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")

        let bobPubKeyTx = try await bobChat.publishKeyAndWait()
        logTx(label: "Bob publishes key", txid: bobPubKeyTx,
            from: bobAccount.address.description, to: bobAccount.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let message1 = "Hey Bob! This is Alice. Can you hear me? 🎉"
        let aliceToBobConv = try await aliceChat.conversation(with: bobAccount.address)
        let result1 = try await aliceChat.send(message1, to: aliceToBobConv, options: .confirmed)
        logTx(label: "Alice -> Bob (message 1)", txid: result1.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: message1)

        let message2 = "Hi Alice! Yes I can! This is amazing! 🚀"
        let bobToAliceConv = try await bobChat.conversation(with: aliceAccount.address)
        let result2 = try await bobChat.send(message2, to: bobToAliceConv, options: .confirmed)
        logTx(label: "Bob -> Alice (message 2)", txid: result2.txid,
            from: bobAccount.address.description, to: aliceAccount.address.description,
            plaintext: message2)

        let message3 = "Encrypted blockchain messaging works! 💎"
        let result3 = try await aliceChat.send(message3, to: aliceToBobConv, options: .confirmed)
        logTx(label: "Alice -> Bob (message 3)", txid: result3.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: message3)

        try await waitForChatMessages(for: bobAccount.address, count: 3, algokit: algokit)
        try await waitForChatMessages(for: aliceAccount.address, count: 4, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob")

        let receivedByBob = bobConv.receivedMessages.map { $0.content }
        verify("Bob received message 1",
            expected: "contains \"\(message1)\"",
            actual: "\(receivedByBob)",
            pass: receivedByBob.contains(message1))
        #expect(receivedByBob.contains(message1))

        verify("Bob received message 3",
            expected: "contains \"\(message3)\"",
            actual: "\(receivedByBob)",
            pass: receivedByBob.contains(message3))
        #expect(receivedByBob.contains(message3))

        var aliceConv = try await aliceChat.conversation(with: bobAccount.address)
        aliceConv = try await aliceChat.refresh(aliceConv)
        logConversation(aliceConv, owner: "Alice")

        let receivedByAlice = aliceConv.receivedMessages.map { $0.content }
        verify("Alice received message 2",
            expected: "contains \"\(message2)\"",
            actual: "\(receivedByAlice)",
            pass: receivedByAlice.contains(message2))
        #expect(receivedByAlice.contains(message2))

        let aliceConversations = try await aliceChat.conversations()
        let bobConversations = try await bobChat.conversations()

        verify("Alice conversation count",
            expected: ">= 1", actual: "\(aliceConversations.count)",
            pass: aliceConversations.count >= 1)

        verify("Bob conversation count",
            expected: ">= 1", actual: "\(bobConversations.count)",
            pass: bobConversations.count >= 1)

        print("\n   TEST 1 COMPLETE")
    }

    @Test("Message encryption is secure - wrong key cannot decrypt")
    func testEncryptionSecurity() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 2: Message encryption is secure - wrong key cannot decrypt")
        print(String(repeating: "=", count: 70))

        let alice = try Account()
        let bob = try Account()
        let eve = try Account()

        print("\n   [SETUP] Created accounts:")
        print("           Alice: \(alice.address)")
        print("           Bob:   \(bob.address)")
        print("           Eve:   \(eve.address) (eavesdropper)")

        try fundAccount(alice)
        try fundAccount(bob)
        try fundAccount(eve)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: alice)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bob)
        let eveChat = try await AlgoChat(configuration: .localnet(), account: eve)

        let aliceKeyTx = try await aliceChat.publishKeyAndWait()
        logTx(label: "Alice publishes key", txid: aliceKeyTx,
            from: alice.address.description, to: alice.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")
        let bobKeyTx = try await bobChat.publishKeyAndWait()
        logTx(label: "Bob publishes key", txid: bobKeyTx,
            from: bob.address.description, to: bob.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: alice.address, algokit: algokit)
        try await waitForTransaction(from: bob.address, algokit: algokit)

        let secretMessage = "This is a secret message only for Bob!"
        let aliceToBob = try await aliceChat.conversation(with: bob.address)
        let sendResult = try await aliceChat.send(secretMessage, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob (secret)", txid: sendResult.txid,
            from: alice.address.description, to: bob.address.description,
            plaintext: secretMessage)

        try await waitForChatMessages(for: bob.address, count: 2, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: alice.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob")

        let bobDecrypted = bobConv.receivedMessages.contains { $0.content == secretMessage }
        verify("Bob decrypts secret message",
            expected: "true (message readable)", actual: "\(bobDecrypted)",
            pass: bobDecrypted)
        #expect(bobDecrypted)

        var eveFromAlice = try await eveChat.conversation(with: alice.address)
        eveFromAlice = try await eveChat.refresh(eveFromAlice)
        var eveFromBob = try await eveChat.conversation(with: bob.address)
        eveFromBob = try await eveChat.refresh(eveFromBob)

        verify("Eve messages from Alice",
            expected: "0 (empty)", actual: "\(eveFromAlice.messageCount) messages",
            pass: eveFromAlice.isEmpty)
        #expect(eveFromAlice.isEmpty)

        verify("Eve messages from Bob",
            expected: "0 (empty)", actual: "\(eveFromBob.messageCount) messages",
            pass: eveFromBob.isEmpty)
        #expect(eveFromBob.isEmpty)

        print("\n   TEST 2 COMPLETE")
    }

    @Test("Publish key function works correctly")
    func testPublishKey() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 3: Publish key function works correctly")
        print(String(repeating: "=", count: 70))

        let account = try Account()
        print("\n   [SETUP] Account: \(account.address)")
        try fundAccount(account, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let chat = try await AlgoChat(configuration: .localnet(), account: account)

        let balance = try await chat.balance()
        verify("Account has funds",
            expected: ">= 1000000 microAlgos", actual: "\(balance.value) microAlgos",
            pass: balance.value >= 1_000_000)
        #expect(balance.value >= 1_000_000)

        let txid = try await chat.publishKeyAndWait()
        logTx(label: "Publish key", txid: txid,
            from: account.address.description, to: account.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")

        verify("Transaction ID non-empty",
            expected: "non-empty string", actual: "\"\(txid)\" (len=\(txid.count))",
            pass: !txid.isEmpty)
        #expect(!txid.isEmpty)

        print("\n   TEST 3 COMPLETE")
    }

    @Test("Self-messaging works correctly with indexer wait")
    func testSelfMessaging() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 4: Self-messaging works correctly with indexer wait")
        print(String(repeating: "=", count: 70))

        let account = try Account()
        print("\n   [SETUP] Account: \(account.address)")
        try fundAccount(account, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let chat = try await AlgoChat(configuration: .localnet(), account: account)

        let keyTx = try await chat.publishKeyAndWait()
        logTx(label: "Publish key", txid: keyTx,
            from: account.address.description, to: account.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: account.address, algokit: algokit)

        let selfMessage = "Hello, myself! Testing self-messaging with indexer wait. 🪞"
        let selfConv = try await chat.conversation(with: account.address)
        let result = try await chat.send(selfMessage, to: selfConv, options: .indexed)
        logTx(label: "Self-message 1", txid: result.txid,
            from: account.address.description, to: account.address.description,
            plaintext: selfMessage)

        var refreshedConv = try await chat.refresh(selfConv)
        logConversation(refreshedConv, owner: "Self")

        let sentContains = refreshedConv.sentMessages.contains { $0.content == selfMessage }
        verify("Self-message appears in sentMessages",
            expected: "true", actual: "\(sentContains)",
            pass: sentContains)
        #expect(sentContains)

        let conversations = try await chat.conversations()
        let selfConversation = conversations.first { $0.participant == account.address }

        verify("Self-conversation exists",
            expected: "non-nil", actual: selfConversation == nil ? "nil" : "found (\(selfConversation?.messageCount ?? 0) msgs)",
            pass: selfConversation != nil)
        #expect(selfConversation != nil)

        let secondMessage = "This is my second message to myself! 🎯"
        let result2 = try await chat.send(secondMessage, to: refreshedConv, options: .indexed)
        logTx(label: "Self-message 2", txid: result2.txid,
            from: account.address.description, to: account.address.description,
            plaintext: secondMessage)

        refreshedConv = try await chat.refresh(refreshedConv)
        logConversation(refreshedConv, owner: "Self (after 2nd)")

        let allSent = refreshedConv.sentMessages.map { $0.content }
        verify("First self-message still present",
            expected: "contains \"\(selfMessage)\"", actual: "\(allSent)",
            pass: allSent.contains(selfMessage))
        #expect(allSent.contains(selfMessage))

        verify("Second self-message present",
            expected: "contains \"\(secondMessage)\"", actual: "\(allSent)",
            pass: allSent.contains(secondMessage))
        #expect(allSent.contains(secondMessage))

        print("\n   TEST 4 COMPLETE")
    }

    // MARK: - PSK Integration Tests

    @Test("PSK messaging flow between two users")
    func testPSKMessagingFlow() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 5: PSK messaging flow between two users")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-alice-\(UUID().uuidString.prefix(8))")
        let bobPSKStorage = try FilePSKStorage(directoryName: ".algochat-test-bob-\(UUID().uuidString.prefix(8))")

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount, pskStorage: bobPSKStorage)

        let aliceKeyTx = try await aliceChat.publishKeyAndWait()
        logTx(label: "Alice publishes key", txid: aliceKeyTx,
            from: aliceAccount.address.description, to: aliceAccount.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")
        let bobKeyTx = try await bobChat.publishKeyAndWait()
        logTx(label: "Bob publishes key", txid: bobKeyTx,
            from: bobAccount.address.description, to: bobAccount.address.description,
            plaintext: "<key-publish-payload>", amount: "0 ALGO")

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        var pskBytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { pskBytes[i] = UInt8(i) }
        let sharedPSK = Data(pskBytes)
        print("   [PSK] Shared PSK (hex): \(sharedPSK.map { String(format: "%02x", $0) }.joined())")

        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: sharedPSK, label: "Bob")
        try await bobChat.addPSKContact(address: aliceAccount.address.description, psk: sharedPSK, label: "Alice")
        print("   [PSK] Contacts exchanged out-of-band")

        let pskMsg1 = "Hello Bob via PSK!"
        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        let result1 = try await aliceChat.sendPSK(pskMsg1, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob (PSK)", txid: result1.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: pskMsg1, protocol: "psk")

        verify("Alice PSK message protocolMode",
            expected: ".psk", actual: "\(result1.message.protocolMode?.rawValue ?? "nil")",
            pass: result1.message.protocolMode == .psk)
        #expect(result1.message.protocolMode == .psk)

        let pskMsg2 = "Hello Alice, PSK received!"
        let bobToAlice = try await bobChat.conversation(with: aliceAccount.address)
        let result2 = try await bobChat.sendPSK(pskMsg2, to: bobToAlice, options: .confirmed)
        logTx(label: "Bob -> Alice (PSK)", txid: result2.txid,
            from: bobAccount.address.description, to: aliceAccount.address.description,
            plaintext: pskMsg2, protocol: "psk")

        verify("Bob PSK reply protocolMode",
            expected: ".psk", actual: "\(result2.message.protocolMode?.rawValue ?? "nil")",
            pass: result2.message.protocolMode == .psk)
        #expect(result2.message.protocolMode == .psk)

        print("\n   TEST 5 COMPLETE")
    }

    @Test("Mixed protocol conversation (standard then PSK)")
    func testMixedProtocolConversation() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 6: Mixed protocol conversation (standard then PSK)")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-mixed-\(UUID().uuidString.prefix(8))")
        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let stdMsg = "Standard message first"
        let conv = try await aliceChat.conversation(with: bobAccount.address)
        let result1 = try await aliceChat.send(stdMsg, to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (standard)", txid: result1.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: stdMsg, protocol: "standard")

        var pskBytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { pskBytes[i] = UInt8(0xFF - i) }
        let sharedPSK = Data(pskBytes)
        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: sharedPSK)
        print("   [PSK] Added Bob as PSK contact")

        let pskMsg = "Now using PSK mode"
        let result2 = try await aliceChat.sendPSK(pskMsg, to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (PSK)", txid: result2.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: pskMsg, protocol: "psk")

        verify("PSK message protocolMode",
            expected: ".psk", actual: "\(result2.message.protocolMode?.rawValue ?? "nil")",
            pass: result2.message.protocolMode == .psk)
        #expect(result2.message.protocolMode == .psk)

        print("\n   TEST 6 COMPLETE")
    }

    @Test("Standard mode is unaffected by PSK code changes")
    func testStandardModeUnaffected() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 7: Standard mode is unaffected by PSK code changes")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")
        print("   [SETUP] No PSK storage configured (standard-only)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let msg = "Standard mode works!"
        let conv = try await aliceChat.conversation(with: bobAccount.address)
        let result = try await aliceChat.send(msg, to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (standard-only)", txid: result.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: msg, protocol: "standard")

        verify("Transaction ID non-empty",
            expected: "non-empty string", actual: "\"\(result.txid)\" (len=\(result.txid.count))",
            pass: !result.txid.isEmpty)
        #expect(!result.txid.isEmpty)

        print("\n   TEST 7 COMPLETE")
    }

    // MARK: - v1.0 Standard Mode Deep Tests

    @Test("Reply messages preserve context on-chain")
    func testReplyMessages() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 8: Reply messages preserve context on-chain")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let originalText = "Hey Bob, what do you think about blockchain messaging?"
        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        let originalResult = try await aliceChat.send(originalText, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob (original)", txid: originalResult.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: originalText)

        try await waitForChatMessages(for: bobAccount.address, count: 2, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob")
        let aliceMsg = bobConv.receivedMessages.first { $0.content == originalText }

        verify("Bob received original message",
            expected: "non-nil message with content \"\(originalText)\"",
            actual: aliceMsg == nil ? "nil" : "found: \"\(aliceMsg?.content ?? "")\"",
            pass: aliceMsg != nil)
        #expect(aliceMsg != nil)

        let replyText = "I think it's the future of private communication!"
        let replyOptions = SendOptions.replying(to: aliceMsg ?? originalResult.message, confirmed: true)
        let replyResult = try await bobChat.send(replyText, to: bobConv, options: replyOptions)
        logTx(label: "Bob -> Alice (reply)", txid: replyResult.txid,
            from: bobAccount.address.description, to: aliceAccount.address.description,
            plaintext: replyText)
        print("         replyTo:   \(replyResult.message.replyContext?.messageId ?? "none")")
        print("         preview:   \"\(replyResult.message.replyContext?.preview ?? "none")\"")

        verify("Optimistic reply isReply",
            expected: "true", actual: "\(replyResult.message.isReply)",
            pass: replyResult.message.isReply)
        #expect(replyResult.message.isReply)

        verify("Optimistic reply has replyContext",
            expected: "non-nil", actual: replyResult.message.replyContext == nil ? "nil" : "present",
            pass: replyResult.message.replyContext != nil)
        #expect(replyResult.message.replyContext != nil)

        let previewContains = replyResult.message.replyContext?.preview.contains("blockchain messaging") == true
        verify("Reply preview contains original text",
            expected: "contains \"blockchain messaging\"",
            actual: "\"\(replyResult.message.replyContext?.preview ?? "")\"",
            pass: previewContains)
        #expect(previewContains)

        try await waitForChatMessages(for: bobAccount.address, count: 3, algokit: algokit)

        var aliceConv = try await aliceChat.conversation(with: bobAccount.address)
        aliceConv = try await aliceChat.refresh(aliceConv)
        logConversation(aliceConv, owner: "Alice")

        let bobReply = aliceConv.receivedMessages.first { $0.content == replyText }
        verify("Alice sees Bob's reply",
            expected: "non-nil message with content \"\(replyText)\"",
            actual: bobReply == nil ? "nil" : "found: \"\(bobReply?.content ?? "")\"",
            pass: bobReply != nil)
        #expect(bobReply != nil)

        verify("Fetched reply isReply",
            expected: "true", actual: "\(bobReply?.isReply ?? false)",
            pass: bobReply?.isReply == true)
        #expect(bobReply?.isReply == true)

        verify("Reply context messageId matches original txid",
            expected: "\(originalResult.txid)",
            actual: "\(bobReply?.replyContext?.messageId ?? "nil")",
            pass: bobReply?.replyContext?.messageId == originalResult.txid)
        #expect(bobReply?.replyContext?.messageId == originalResult.txid)

        print("\n   TEST 8 COMPLETE")
    }

    @Test("Custom payment amount attached to messages")
    func testCustomPaymentAmount() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 9: Custom payment amount attached to messages")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let bobBalanceBefore = try await bobChat.balance()
        print("   [BALANCE] Bob before: \(bobBalanceBefore.value) microAlgos")

        let customAmount = MicroAlgos(50_000)
        let customMsg = "Here's 0.05 ALGO with this message!"
        let options = SendOptions.withAmount(customAmount, confirmed: true)
        let conv = try await aliceChat.conversation(with: bobAccount.address)
        let result = try await aliceChat.send(customMsg, to: conv, options: options)
        logTx(label: "Alice -> Bob (custom amount)", txid: result.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: customMsg, amount: "50000 microAlgos (0.05 ALGO)")

        verify("Transaction ID non-empty",
            expected: "non-empty", actual: "\"\(result.txid)\"",
            pass: !result.txid.isEmpty)
        #expect(!result.txid.isEmpty)

        let bobBalanceAfter = try await bobChat.balance()
        let increase = bobBalanceAfter.value - bobBalanceBefore.value
        print("   [BALANCE] Bob after:  \(bobBalanceAfter.value) microAlgos")
        print("   [BALANCE] Increase:   \(increase) microAlgos")

        verify("Bob balance increased by >= 50000",
            expected: ">= 50000 microAlgos", actual: "\(increase) microAlgos",
            pass: increase >= 50_000)
        #expect(increase >= 50_000)

        let defaultMsg = "This one has the default amount"
        let result2 = try await aliceChat.send(defaultMsg, to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (default amount)", txid: result2.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: defaultMsg, amount: "1000 microAlgos (0.001 ALGO default)")

        verify("Default amount TX non-empty",
            expected: "non-empty", actual: "\"\(result2.txid)\"",
            pass: !result2.txid.isEmpty)
        #expect(!result2.txid.isEmpty)

        print("\n   TEST 9 COMPLETE")
    }

    @Test("Large message near max payload roundtrips")
    func testLargeMessageNearMaxPayload() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 10: Large message near max payload roundtrips")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let repeatedText = "ABCDEFGHIJ"
        var largeMessage = ""
        for i in 0..<60 { largeMessage += "\(repeatedText)\(i)-" }
        let utf8Data = Data(largeMessage.utf8)
        if utf8Data.count > 750 { largeMessage = String(largeMessage.prefix(750)) }
        let byteCount = Data(largeMessage.utf8).count
        print("   [PAYLOAD] Sending \(byteCount) bytes, \(largeMessage.count) characters")
        print("   [PAYLOAD] Max envelope payload: \(ChatEnvelope.maxPayloadSize) bytes")
        print("   [PAYLOAD] First 80 chars: \"\(largeMessage.prefix(80))...\"")

        let conv = try await aliceChat.conversation(with: bobAccount.address)
        let result = try await aliceChat.send(largeMessage, to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (large message)", txid: result.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: "[\(byteCount) bytes] \(largeMessage.prefix(60))...")

        try await waitForChatMessages(for: bobAccount.address, count: 2, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)

        let received = bobConv.receivedMessages.first { $0.content == largeMessage }
        let receivedLen = received?.content.count ?? 0

        verify("Bob received large message with exact content",
            expected: "non-nil, \(largeMessage.count) chars",
            actual: received == nil ? "nil" : "\(receivedLen) chars",
            pass: received != nil)
        #expect(received != nil)

        verify("Received length matches sent length",
            expected: "\(largeMessage.count)", actual: "\(receivedLen)",
            pass: receivedLen == largeMessage.count)
        #expect(received?.content.count == largeMessage.count)

        print("\n   TEST 10 COMPLETE (roundtripped \(byteCount) bytes)")
    }

    @Test("Three-party independent conversations")
    func testMultiPartyConversations() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 11: Three-party independent conversations")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        let carolAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")
        print("   [SETUP] Carol: \(carolAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try fundAccount(carolAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)
        let carolChat = try await AlgoChat(configuration: .localnet(), account: carolAccount)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()
        _ = try await carolChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)
        try await waitForTransaction(from: carolAccount.address, algokit: algokit)

        let msg1 = "Hi Bob from Alice!"
        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        let r1 = try await aliceChat.send(msg1, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob", txid: r1.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description, plaintext: msg1)

        let msg2 = "Hi Carol from Alice!"
        let aliceToCarol = try await aliceChat.conversation(with: carolAccount.address)
        let r2 = try await aliceChat.send(msg2, to: aliceToCarol, options: .confirmed)
        logTx(label: "Alice -> Carol", txid: r2.txid,
            from: aliceAccount.address.description, to: carolAccount.address.description, plaintext: msg2)

        let msg3 = "Hi Carol from Bob!"
        let bobToCarol = try await bobChat.conversation(with: carolAccount.address)
        let r3 = try await bobChat.send(msg3, to: bobToCarol, options: .confirmed)
        logTx(label: "Bob -> Carol", txid: r3.txid,
            from: bobAccount.address.description, to: carolAccount.address.description, plaintext: msg3)

        try await waitForChatMessages(for: bobAccount.address, count: 2, algokit: algokit)
        try await waitForChatMessages(for: carolAccount.address, count: 3, algokit: algokit)

        let aliceConvs = try await aliceChat.conversations()
        let bobConvs = try await bobChat.conversations()
        let carolConvs = try await carolChat.conversations()

        verify("Alice conversation count >= 2",
            expected: ">= 2", actual: "\(aliceConvs.count)", pass: aliceConvs.count >= 2)
        #expect(aliceConvs.count >= 2)
        verify("Bob conversation count >= 2",
            expected: ">= 2", actual: "\(bobConvs.count)", pass: bobConvs.count >= 2)
        #expect(bobConvs.count >= 2)
        verify("Carol conversation count >= 2",
            expected: ">= 2", actual: "\(carolConvs.count)", pass: carolConvs.count >= 2)
        #expect(carolConvs.count >= 2)

        var bobFromAlice = try await bobChat.conversation(with: aliceAccount.address)
        bobFromAlice = try await bobChat.refresh(bobFromAlice)
        logConversation(bobFromAlice, owner: "Bob (from Alice)")
        let bobGotMsg = bobFromAlice.receivedMessages.contains { $0.content == msg1 }
        verify("Bob received \"Hi Bob from Alice!\"",
            expected: "true", actual: "\(bobGotMsg)", pass: bobGotMsg)
        #expect(bobGotMsg)

        var carolFromAlice = try await carolChat.conversation(with: aliceAccount.address)
        carolFromAlice = try await carolChat.refresh(carolFromAlice)
        logConversation(carolFromAlice, owner: "Carol (from Alice)")
        let carolGotAlice = carolFromAlice.receivedMessages.contains { $0.content == msg2 }
        verify("Carol received \"Hi Carol from Alice!\"",
            expected: "true", actual: "\(carolGotAlice)", pass: carolGotAlice)
        #expect(carolGotAlice)

        var carolFromBob = try await carolChat.conversation(with: bobAccount.address)
        carolFromBob = try await carolChat.refresh(carolFromBob)
        logConversation(carolFromBob, owner: "Carol (from Bob)")
        let carolGotBob = carolFromBob.receivedMessages.contains { $0.content == msg3 }
        verify("Carol received \"Hi Carol from Bob!\"",
            expected: "true", actual: "\(carolGotBob)", pass: carolGotBob)
        #expect(carolGotBob)

        print("\n   TEST 11 COMPLETE")
    }

    @Test("Incremental refresh picks up new messages")
    func testConversationRefreshPagination() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 12: Incremental refresh picks up new messages")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let conv = try await aliceChat.conversation(with: bobAccount.address)
        let r1 = try await aliceChat.send("Message 1 of 3", to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (msg 1)", txid: r1.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: "Message 1 of 3")
        let r2 = try await aliceChat.send("Message 2 of 3", to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (msg 2)", txid: r2.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: "Message 2 of 3")

        try await waitForChatMessages(for: bobAccount.address, count: 3, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob (first refresh)")

        verify("Bob received count >= 2 after first refresh",
            expected: ">= 2", actual: "\(bobConv.receivedMessages.count)",
            pass: bobConv.receivedMessages.count >= 2)
        #expect(bobConv.receivedMessages.count >= 2)

        let lastRound = bobConv.lastFetchedRound
        verify("lastFetchedRound is set",
            expected: "non-nil", actual: "\(lastRound ?? 0)",
            pass: lastRound != nil)
        #expect(lastRound != nil)

        let r3 = try await aliceChat.send("Message 3 of 3", to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (msg 3)", txid: r3.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: "Message 3 of 3")

        try await waitForChatMessages(for: bobAccount.address, count: 4, algokit: algokit)

        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob (incremental refresh)")

        let contents = bobConv.receivedMessages.map { $0.content }
        verify("Contains \"Message 1 of 3\"",
            expected: "true", actual: "\(contents.contains("Message 1 of 3"))",
            pass: contents.contains("Message 1 of 3"))
        #expect(contents.contains("Message 1 of 3"))
        verify("Contains \"Message 2 of 3\"",
            expected: "true", actual: "\(contents.contains("Message 2 of 3"))",
            pass: contents.contains("Message 2 of 3"))
        #expect(contents.contains("Message 2 of 3"))
        verify("Contains \"Message 3 of 3\"",
            expected: "true", actual: "\(contents.contains("Message 3 of 3"))",
            pass: contents.contains("Message 3 of 3"))
        #expect(contents.contains("Message 3 of 3"))

        let uniqueIds = Set(bobConv.messages.map { $0.id })
        verify("No duplicate messages",
            expected: "\(bobConv.messageCount) unique IDs", actual: "\(uniqueIds.count) unique IDs",
            pass: uniqueIds.count == bobConv.messageCount)
        #expect(uniqueIds.count == bobConv.messageCount)

        print("\n   TEST 12 COMPLETE")
    }

    // MARK: - v1.1 PSK Mode Deep Tests

    @Test("Multi-message PSK conversation with counter advancement")
    func testPSKMultiMessageConversation() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 13: Multi-message PSK conversation with counter advancement")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 20_000_000)
        try fundAccount(bobAccount, amount: 20_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-multi-\(UUID().uuidString.prefix(8))")
        let bobPSKStorage = try FilePSKStorage(directoryName: ".algochat-test-multi-bob-\(UUID().uuidString.prefix(8))")

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount, pskStorage: bobPSKStorage)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        var pskBytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { pskBytes[i] = UInt8(i &+ 0x10) }
        let sharedPSK = Data(pskBytes)
        print("   [PSK] Shared PSK (hex): \(sharedPSK.map { String(format: "%02x", $0) }.joined())")

        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: sharedPSK, label: "Bob")
        try await bobChat.addPSKContact(address: aliceAccount.address.description, psk: sharedPSK, label: "Alice")

        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        for i in 1...3 {
            let text = "Alice PSK message \(i)"
            let r = try await aliceChat.sendPSK(text, to: aliceToBob, options: .confirmed)
            logTx(label: "Alice -> Bob (PSK #\(i))", txid: r.txid,
                from: aliceAccount.address.description, to: bobAccount.address.description,
                plaintext: text, protocol: "psk")
            verify("Alice msg \(i) protocolMode",
                expected: ".psk", actual: "\(r.message.protocolMode?.rawValue ?? "nil")",
                pass: r.message.protocolMode == .psk)
            #expect(r.message.protocolMode == .psk)
        }

        let bobToAlice = try await bobChat.conversation(with: aliceAccount.address)
        for i in 1...2 {
            let text = "Bob PSK message \(i)"
            let r = try await bobChat.sendPSK(text, to: bobToAlice, options: .confirmed)
            logTx(label: "Bob -> Alice (PSK #\(i))", txid: r.txid,
                from: bobAccount.address.description, to: aliceAccount.address.description,
                plaintext: text, protocol: "psk")
            verify("Bob msg \(i) protocolMode",
                expected: ".psk", actual: "\(r.message.protocolMode?.rawValue ?? "nil")",
                pass: r.message.protocolMode == .psk)
            #expect(r.message.protocolMode == .psk)
        }

        try await waitForChatMessages(for: bobAccount.address, count: 6, algokit: algokit)
        try await waitForChatMessages(for: aliceAccount.address, count: 6, algokit: algokit)

        var aliceConv = try await aliceChat.conversation(with: bobAccount.address)
        aliceConv = try await aliceChat.refresh(aliceConv)
        logConversation(aliceConv, owner: "Alice")

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob")

        let aliceReceived = aliceConv.receivedMessages.map { $0.content }
        let bobReceived = bobConv.receivedMessages.map { $0.content }

        let aliceSeesAny = aliceReceived.contains { $0.hasPrefix("Bob PSK message") }
        verify("Alice sees at least 1 Bob PSK message",
            expected: "true", actual: "\(aliceSeesAny) (received: \(aliceReceived))",
            pass: aliceSeesAny)
        #expect(aliceSeesAny)

        let bobSeesAny = bobReceived.contains { $0.hasPrefix("Alice PSK message") }
        verify("Bob sees at least 1 Alice PSK message",
            expected: "true", actual: "\(bobSeesAny) (received: \(bobReceived))",
            pass: bobSeesAny)
        #expect(bobSeesAny)

        verify("Alice total messages >= 2",
            expected: ">= 2", actual: "\(aliceConv.messageCount)",
            pass: aliceConv.messageCount >= 2)
        #expect(aliceConv.messageCount >= 2)

        verify("Bob total messages >= 2",
            expected: ">= 2", actual: "\(bobConv.messageCount)",
            pass: bobConv.messageCount >= 2)
        #expect(bobConv.messageCount >= 2)

        let alicePSK = aliceConv.messages.filter { $0.protocolMode == .psk }
        let bobPSK = bobConv.messages.filter { $0.protocolMode == .psk }
        verify("Alice has PSK-mode messages",
            expected: "> 0", actual: "\(alicePSK.count)", pass: !alicePSK.isEmpty)
        #expect(!alicePSK.isEmpty)
        verify("Bob has PSK-mode messages",
            expected: "> 0", actual: "\(bobPSK.count)", pass: !bobPSK.isEmpty)
        #expect(!bobPSK.isEmpty)

        print("\n   TEST 13 COMPLETE")
    }

    @Test("Sender can read their own PSK messages via refresh")
    func testPSKBidirectionalDecryptionOnChain() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 14: Sender can read their own PSK messages via refresh")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-bidir-\(UUID().uuidString.prefix(8))")
        let bobPSKStorage = try FilePSKStorage(directoryName: ".algochat-test-bidir-bob-\(UUID().uuidString.prefix(8))")

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount, pskStorage: bobPSKStorage)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let sharedPSK = Data((0..<32).map { UInt8($0 &+ 0x20) })
        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: sharedPSK, label: "Bob")
        try await bobChat.addPSKContact(address: aliceAccount.address.description, psk: sharedPSK, label: "Alice")

        let messageText = "PSK message for bidirectional test"
        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        let result = try await aliceChat.sendPSK(messageText, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob (PSK bidir)", txid: result.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: messageText, protocol: "psk")

        try await waitForChatMessages(for: bobAccount.address, count: 2, algokit: algokit)
        try await waitForChatMessages(for: aliceAccount.address, count: 2, algokit: algokit)

        var aliceConv = try await aliceChat.conversation(with: bobAccount.address)
        aliceConv = try await aliceChat.refresh(aliceConv)
        logConversation(aliceConv, owner: "Alice (sender)")

        let aliceSeesSent = aliceConv.sentMessages.contains { $0.content == messageText }
        verify("Alice sees her own sent PSK message",
            expected: "true", actual: "\(aliceSeesSent) (sent: \(aliceConv.sentMessages.map { $0.content }))",
            pass: aliceSeesSent)
        #expect(aliceSeesSent)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob (recipient)")

        let bobSeesReceived = bobConv.receivedMessages.contains { $0.content == messageText }
        verify("Bob decrypts Alice's PSK message",
            expected: "true", actual: "\(bobSeesReceived) (received: \(bobConv.receivedMessages.map { $0.content }))",
            pass: bobSeesReceived)
        #expect(bobSeesReceived)

        print("\n   TEST 14 COMPLETE")
    }

    @Test("Third party cannot decrypt PSK messages")
    func testPSKEveCannotDecrypt() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 15: Third party cannot decrypt PSK messages")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        let eveAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")
        print("   [SETUP] Eve:   \(eveAccount.address) (eavesdropper)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try fundAccount(eveAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSK = try FilePSKStorage(directoryName: ".algochat-test-eve-a-\(UUID().uuidString.prefix(8))")
        let bobPSK = try FilePSKStorage(directoryName: ".algochat-test-eve-b-\(UUID().uuidString.prefix(8))")
        let evePSK = try FilePSKStorage(directoryName: ".algochat-test-eve-e-\(UUID().uuidString.prefix(8))")

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSK)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount, pskStorage: bobPSK)
        let eveChat = try await AlgoChat(configuration: .localnet(), account: eveAccount, pskStorage: evePSK)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()
        _ = try await eveChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)
        try await waitForTransaction(from: eveAccount.address, algokit: algokit)

        let pskAB = Data((0..<32).map { UInt8($0 &+ 0x30) })
        print("   [PSK] Alice<->Bob PSK (hex): \(pskAB.map { String(format: "%02x", $0) }.joined())")
        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: pskAB, label: "Bob")
        try await bobChat.addPSKContact(address: aliceAccount.address.description, psk: pskAB, label: "Alice")

        let pskAE = Data((0..<32).map { UInt8($0 &+ 0x60) })
        print("   [PSK] Alice<->Eve PSK (hex): \(pskAE.map { String(format: "%02x", $0) }.joined()) (DIFFERENT)")
        try await eveChat.addPSKContact(address: aliceAccount.address.description, psk: pskAE, label: "Alice")
        try await aliceChat.addPSKContact(address: eveAccount.address.description, psk: pskAE, label: "Eve")

        let secretMsg = "Top secret PSK message only for Bob"
        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        let result = try await aliceChat.sendPSK(secretMsg, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob (PSK secret)", txid: result.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: secretMsg, protocol: "psk")

        try await waitForChatMessages(for: bobAccount.address, count: 2, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob")

        let bobDecrypted = bobConv.receivedMessages.contains { $0.content == secretMsg }
        verify("Bob decrypts PSK message",
            expected: "true (message readable)", actual: "\(bobDecrypted)",
            pass: bobDecrypted)
        #expect(bobDecrypted)

        var eveFromAlice = try await eveChat.conversation(with: aliceAccount.address)
        eveFromAlice = try await eveChat.refresh(eveFromAlice)
        logConversation(eveFromAlice, owner: "Eve (from Alice)")

        verify("Eve received messages from Alice",
            expected: "0 (cannot decrypt, not the recipient)",
            actual: "\(eveFromAlice.receivedMessages.count)",
            pass: eveFromAlice.receivedMessages.isEmpty)
        #expect(eveFromAlice.receivedMessages.isEmpty)

        print("\n   TEST 15 COMPLETE")
    }

    @Test("Generate URI, parse, add contact, send PSK")
    func testPSKExchangeURIFlow() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 16: Generate URI, parse, add contact, send PSK")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-uri-a-\(UUID().uuidString.prefix(8))")
        let bobPSKStorage = try FilePSKStorage(directoryName: ".algochat-test-uri-b-\(UUID().uuidString.prefix(8))")

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount, pskStorage: bobPSKStorage)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let pskData = Data((0..<32).map { UInt8($0 &+ 0x40) })
        let aliceURI = await aliceChat.generatePSKExchangeURI(psk: pskData, label: "Alice")
        let uriString = aliceURI.toString()
        print("   [URI] Generated: \(uriString)")

        let parsedURI = try PSKExchangeURI.parse(uriString)

        verify("Parsed address matches Alice",
            expected: "\(aliceAccount.address.description)",
            actual: "\(parsedURI.address)",
            pass: parsedURI.address == aliceAccount.address.description)
        #expect(parsedURI.address == aliceAccount.address.description)

        verify("Parsed PSK matches original",
            expected: "\(pskData.map { String(format: "%02x", $0) }.joined())",
            actual: "\(parsedURI.psk.map { String(format: "%02x", $0) }.joined())",
            pass: parsedURI.psk == pskData)
        #expect(parsedURI.psk == pskData)

        verify("Parsed label",
            expected: "\"Alice\"", actual: "\"\(parsedURI.label ?? "nil")\"",
            pass: parsedURI.label == "Alice")
        #expect(parsedURI.label == "Alice")

        try await bobChat.addPSKContact(uri: parsedURI)
        print("   [PSK] Bob added Alice via parsed URI")

        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: pskData, label: "Bob")
        print("   [PSK] Alice added Bob manually with same PSK")

        let msg1 = "Hello via URI exchange!"
        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        let r1 = try await aliceChat.sendPSK(msg1, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob (PSK via URI)", txid: r1.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: msg1, protocol: "psk")
        verify("Alice PSK message protocolMode",
            expected: ".psk", actual: "\(r1.message.protocolMode?.rawValue ?? "nil")",
            pass: r1.message.protocolMode == .psk)
        #expect(r1.message.protocolMode == .psk)

        let msg2 = "Got it via URI!"
        let bobToAlice = try await bobChat.conversation(with: aliceAccount.address)
        let r2 = try await bobChat.sendPSK(msg2, to: bobToAlice, options: .confirmed)
        logTx(label: "Bob -> Alice (PSK reply)", txid: r2.txid,
            from: bobAccount.address.description, to: aliceAccount.address.description,
            plaintext: msg2, protocol: "psk")
        verify("Bob PSK reply protocolMode",
            expected: ".psk", actual: "\(r2.message.protocolMode?.rawValue ?? "nil")",
            pass: r2.message.protocolMode == .psk)
        #expect(r2.message.protocolMode == .psk)

        print("\n   TEST 16 COMPLETE")
    }

    @Test("Add, check, list, remove PSK contacts")
    func testPSKContactLifecycle() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 17: Add, check, list, remove PSK contacts")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        let carolAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")
        print("   [SETUP] Carol: \(carolAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-lifecycle-\(UUID().uuidString.prefix(8))")
        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)

        let bobAddress = bobAccount.address.description
        let carolAddress = carolAccount.address.description

        let initial = try await aliceChat.pskContacts()
        verify("Initial contacts empty",
            expected: "0", actual: "\(initial.count)", pass: initial.isEmpty)
        #expect(initial.isEmpty)

        let bobPSK = Data((0..<32).map { UInt8($0) })
        try await aliceChat.addPSKContact(address: bobAddress, psk: bobPSK, label: "Bob")
        print("   [PSK] Added Bob")

        let hasBob = await aliceChat.hasPSKContact(for: bobAddress)
        verify("hasPSKContact(Bob)",
            expected: "true", actual: "\(hasBob)", pass: hasBob)
        #expect(hasBob)

        let afterBob = try await aliceChat.pskContacts()
        verify("Contact count after adding Bob",
            expected: "1", actual: "\(afterBob.count)", pass: afterBob.count == 1)
        #expect(afterBob.count == 1)
        verify("First contact address is Bob",
            expected: "\(bobAddress)", actual: "\(afterBob.first?.address ?? "nil")",
            pass: afterBob.first?.address == bobAddress)
        #expect(afterBob.first?.address == bobAddress)
        verify("First contact label is Bob",
            expected: "\"Bob\"", actual: "\"\(afterBob.first?.label ?? "nil")\"",
            pass: afterBob.first?.label == "Bob")
        #expect(afterBob.first?.label == "Bob")

        let carolPSK = Data((0..<32).map { UInt8($0 &+ 0x80) })
        try await aliceChat.addPSKContact(address: carolAddress, psk: carolPSK, label: "Carol")
        print("   [PSK] Added Carol")

        let afterCarol = try await aliceChat.pskContacts()
        verify("Contact count after adding Carol",
            expected: "2", actual: "\(afterCarol.count)", pass: afterCarol.count == 2)
        #expect(afterCarol.count == 2)

        try await aliceChat.removePSKContact(for: bobAddress)
        print("   [PSK] Removed Bob")

        let hasBobAfter = await aliceChat.hasPSKContact(for: bobAddress)
        verify("hasPSKContact(Bob) after remove",
            expected: "false", actual: "\(hasBobAfter)", pass: !hasBobAfter)
        #expect(!hasBobAfter)

        let afterRemove = try await aliceChat.pskContacts()
        verify("Contact count after removing Bob",
            expected: "1", actual: "\(afterRemove.count)", pass: afterRemove.count == 1)
        #expect(afterRemove.count == 1)
        verify("Remaining contact is Carol",
            expected: "\(carolAddress)", actual: "\(afterRemove.first?.address ?? "nil")",
            pass: afterRemove.first?.address == carolAddress)
        #expect(afterRemove.first?.address == carolAddress)

        print("\n   TEST 17 COMPLETE")
    }

    // MARK: - Cross-Protocol Localnet Tests

    @Test("Protocol mode preserved through on-chain roundtrip")
    func testProtocolModeInFetchedMessages() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 18: Protocol mode preserved through on-chain roundtrip")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")

        try fundAccount(aliceAccount, amount: 10_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-proto-a-\(UUID().uuidString.prefix(8))")
        let bobPSKStorage = try FilePSKStorage(directoryName: ".algochat-test-proto-b-\(UUID().uuidString.prefix(8))")

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount, pskStorage: bobPSKStorage)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)

        let stdText = "Standard protocol message"
        let conv = try await aliceChat.conversation(with: bobAccount.address)
        let stdResult = try await aliceChat.send(stdText, to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (standard)", txid: stdResult.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: stdText, protocol: "standard")

        let pskData = Data((0..<32).map { UInt8($0 &+ 0x50) })
        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: pskData, label: "Bob")
        try await bobChat.addPSKContact(address: aliceAccount.address.description, psk: pskData, label: "Alice")

        let pskText = "PSK protocol message"
        let pskResult = try await aliceChat.sendPSK(pskText, to: conv, options: .confirmed)
        logTx(label: "Alice -> Bob (PSK)", txid: pskResult.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: pskText, protocol: "psk")

        try await waitForChatMessages(for: bobAccount.address, count: 3, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob")

        verify("Bob received count >= 2",
            expected: ">= 2", actual: "\(bobConv.receivedMessages.count)",
            pass: bobConv.receivedMessages.count >= 2)
        #expect(bobConv.receivedMessages.count >= 2)

        let stdMsg = bobConv.receivedMessages.first { $0.content == stdText }
        let pskMsg = bobConv.receivedMessages.first { $0.content == pskText }

        verify("Standard message found",
            expected: "non-nil with content \"\(stdText)\"",
            actual: stdMsg == nil ? "nil" : "\"\(stdMsg?.content ?? "")\"",
            pass: stdMsg != nil)
        #expect(stdMsg != nil)

        verify("PSK message found",
            expected: "non-nil with content \"\(pskText)\"",
            actual: pskMsg == nil ? "nil" : "\"\(pskMsg?.content ?? "")\"",
            pass: pskMsg != nil)
        #expect(pskMsg != nil)

        verify("Standard message protocolMode",
            expected: ".standard", actual: "\(stdMsg?.protocolMode?.rawValue ?? "nil")",
            pass: stdMsg?.protocolMode == .standard)
        #expect(stdMsg?.protocolMode == .standard)

        verify("PSK message protocolMode",
            expected: ".psk", actual: "\(pskMsg?.protocolMode?.rawValue ?? "nil")",
            pass: pskMsg?.protocolMode == .psk)
        #expect(pskMsg?.protocolMode == .psk)

        print("\n   TEST 18 COMPLETE")
    }

    @Test("Independent PSK sessions with different contacts")
    func testPSKMultipleIndependentContacts() async throws {
        guard isLocalnetRunning() else {
            print("SKIP: localnet is not running")
            return
        }

        print("\n" + String(repeating: "=", count: 70))
        print("TEST 19: Independent PSK sessions with different contacts")
        print(String(repeating: "=", count: 70))

        let aliceAccount = try Account()
        let bobAccount = try Account()
        let carolAccount = try Account()
        print("\n   [SETUP] Alice: \(aliceAccount.address)")
        print("   [SETUP] Bob:   \(bobAccount.address)")
        print("   [SETUP] Carol: \(carolAccount.address)")

        try fundAccount(aliceAccount, amount: 20_000_000)
        try fundAccount(bobAccount, amount: 10_000_000)
        try fundAccount(carolAccount, amount: 10_000_000)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let alicePSKStorage = try FilePSKStorage(directoryName: ".algochat-test-indep-a-\(UUID().uuidString.prefix(8))")
        let bobPSKStorage = try FilePSKStorage(directoryName: ".algochat-test-indep-b-\(UUID().uuidString.prefix(8))")
        let carolPSKStorage = try FilePSKStorage(directoryName: ".algochat-test-indep-c-\(UUID().uuidString.prefix(8))")

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: aliceAccount, pskStorage: alicePSKStorage)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bobAccount, pskStorage: bobPSKStorage)
        let carolChat = try await AlgoChat(configuration: .localnet(), account: carolAccount, pskStorage: carolPSKStorage)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()
        _ = try await carolChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: aliceAccount.address, algokit: algokit)
        try await waitForTransaction(from: bobAccount.address, algokit: algokit)
        try await waitForTransaction(from: carolAccount.address, algokit: algokit)

        let pskAB = Data((0..<32).map { UInt8($0 &+ 0x70) })
        print("   [PSK] Alice<->Bob PSK:   \(pskAB.map { String(format: "%02x", $0) }.joined())")
        try await aliceChat.addPSKContact(address: bobAccount.address.description, psk: pskAB, label: "Bob")
        try await bobChat.addPSKContact(address: aliceAccount.address.description, psk: pskAB, label: "Alice")

        let pskAC = Data((0..<32).map { UInt8($0 &+ 0x90) })
        print("   [PSK] Alice<->Carol PSK: \(pskAC.map { String(format: "%02x", $0) }.joined()) (DIFFERENT)")
        try await aliceChat.addPSKContact(address: carolAccount.address.description, psk: pskAC, label: "Carol")
        try await carolChat.addPSKContact(address: aliceAccount.address.description, psk: pskAC, label: "Alice")

        let bobMsg = "Secret for Bob only"
        let aliceToBob = try await aliceChat.conversation(with: bobAccount.address)
        let rBob = try await aliceChat.sendPSK(bobMsg, to: aliceToBob, options: .confirmed)
        logTx(label: "Alice -> Bob (PSK-AB)", txid: rBob.txid,
            from: aliceAccount.address.description, to: bobAccount.address.description,
            plaintext: bobMsg, protocol: "psk")

        let carolMsg = "Secret for Carol only"
        let aliceToCarol = try await aliceChat.conversation(with: carolAccount.address)
        let rCarol = try await aliceChat.sendPSK(carolMsg, to: aliceToCarol, options: .confirmed)
        logTx(label: "Alice -> Carol (PSK-AC)", txid: rCarol.txid,
            from: aliceAccount.address.description, to: carolAccount.address.description,
            plaintext: carolMsg, protocol: "psk")

        try await waitForChatMessages(for: bobAccount.address, count: 2, algokit: algokit)
        try await waitForChatMessages(for: carolAccount.address, count: 2, algokit: algokit)

        var bobConv = try await bobChat.conversation(with: aliceAccount.address)
        bobConv = try await bobChat.refresh(bobConv)
        logConversation(bobConv, owner: "Bob")

        let bobGotHis = bobConv.receivedMessages.contains { $0.content == bobMsg }
        verify("Bob received his message",
            expected: "contains \"Secret for Bob only\"",
            actual: "\(bobConv.receivedMessages.map { $0.content })",
            pass: bobGotHis)
        #expect(bobGotHis)

        let bobGotCarols = bobConv.receivedMessages.contains { $0.content == carolMsg }
        verify("Bob does NOT see Carol's message",
            expected: "false", actual: "\(bobGotCarols)",
            pass: !bobGotCarols)
        #expect(!bobGotCarols)

        var carolConv = try await carolChat.conversation(with: aliceAccount.address)
        carolConv = try await carolChat.refresh(carolConv)
        logConversation(carolConv, owner: "Carol")

        let carolGotHers = carolConv.receivedMessages.contains { $0.content == carolMsg }
        verify("Carol received her message",
            expected: "contains \"Secret for Carol only\"",
            actual: "\(carolConv.receivedMessages.map { $0.content })",
            pass: carolGotHers)
        #expect(carolGotHers)

        let carolGotBobs = carolConv.receivedMessages.contains { $0.content == bobMsg }
        verify("Carol does NOT see Bob's message",
            expected: "false", actual: "\(carolGotBobs)",
            pass: !carolGotBobs)
        #expect(!carolGotBobs)

        print("\n   TEST 19 COMPLETE")
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
