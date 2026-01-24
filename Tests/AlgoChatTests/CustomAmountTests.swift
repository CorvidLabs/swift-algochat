import Algorand
import AlgoKit
@preconcurrency import Crypto
import Foundation
import Testing
@testable import AlgoChat

@Suite("Custom Payment Amount Tests")
struct CustomAmountTests {

    // MARK: - SendOptions Unit Tests

    @Test("withAmount creates options with specified amount")
    func testWithAmountCreatesCorrectOptions() {
        let amount = MicroAlgos(500_000) // 0.5 ALGO
        let options = SendOptions.withAmount(amount)

        #expect(options.amount == amount)
        #expect(options.waitForConfirmation == false)
        #expect(options.waitForIndexer == false)
        #expect(options.timeout == 10)
        #expect(options.replyContext == nil)
    }

    @Test("withAmount with confirmed flag")
    func testWithAmountConfirmed() {
        let amount = MicroAlgos(1_000_000) // 1 ALGO
        let options = SendOptions.withAmount(amount, confirmed: true)

        #expect(options.amount == amount)
        #expect(options.waitForConfirmation == true)
        #expect(options.waitForIndexer == false)
    }

    @Test("withAmount with indexed flag")
    func testWithAmountIndexed() {
        let amount = MicroAlgos(2_000_000) // 2 ALGO
        let options = SendOptions.withAmount(amount, indexed: true)

        #expect(options.amount == amount)
        #expect(options.waitForConfirmation == true) // indexed implies confirmed
        #expect(options.waitForIndexer == true)
    }

    @Test("withAmount with custom timeout")
    func testWithAmountCustomTimeout() {
        let amount = MicroAlgos(100_000)
        let options = SendOptions.withAmount(amount, timeout: 20)

        #expect(options.amount == amount)
        #expect(options.timeout == 20)
    }

    @Test("withAmount with all parameters")
    func testWithAmountAllParameters() {
        let amount = MicroAlgos(5_000_000) // 5 ALGO
        let options = SendOptions.withAmount(amount, confirmed: true, indexed: true, timeout: 15)

        #expect(options.amount == amount)
        #expect(options.waitForConfirmation == true)
        #expect(options.waitForIndexer == true)
        #expect(options.timeout == 15)
    }

    @Test("Default options have nil amount")
    func testDefaultOptionsHaveNilAmount() {
        let options = SendOptions.default

        #expect(options.amount == nil)
    }

    @Test("Confirmed options have nil amount")
    func testConfirmedOptionsHaveNilAmount() {
        let options = SendOptions.confirmed

        #expect(options.amount == nil)
    }

    @Test("Indexed options have nil amount")
    func testIndexedOptionsHaveNilAmount() {
        let options = SendOptions.indexed

        #expect(options.amount == nil)
    }

    @Test("Init with amount parameter")
    func testInitWithAmount() {
        let amount = MicroAlgos(750_000)
        let options = SendOptions(amount: amount)

        #expect(options.amount == amount)
        #expect(options.waitForConfirmation == false)
        #expect(options.timeout == 10)
    }

    // MARK: - Edge Case Tests

    @Test("Minimum amount (1 microAlgo)")
    func testMinimumAmount() {
        let amount = MicroAlgos(1)
        let options = SendOptions.withAmount(amount)

        #expect(options.amount == amount)
        #expect(options.amount?.value == 1)
    }

    @Test("Zero amount")
    func testZeroAmount() {
        let amount = MicroAlgos(0)
        let options = SendOptions.withAmount(amount)

        #expect(options.amount == amount)
        #expect(options.amount?.value == 0)
    }

    @Test("Large amount (1 billion ALGO)")
    func testLargeAmount() {
        // 1 billion ALGO = 1_000_000_000 * 1_000_000 microAlgos
        let amount = MicroAlgos(1_000_000_000_000_000)
        let options = SendOptions.withAmount(amount)

        #expect(options.amount == amount)
        #expect(options.amount?.value == 1_000_000_000_000_000)
    }

    @Test("Standard minimum payment amount")
    func testStandardMinimumPayment() {
        let amount = MessageTransaction.minimumPayment // 1000 microAlgos
        let options = SendOptions.withAmount(amount)

        #expect(options.amount == amount)
        #expect(options.amount?.value == 1000)
    }

    // MARK: - MessageTransaction Constants

    @Test("MessageTransaction minimum payment constant")
    func testMinimumPaymentConstant() {
        #expect(MessageTransaction.minimumPayment.value == 1000)
    }

    // MARK: - Replying with Amount Tests

    @Test("Replying with custom amount")
    func testReplyingWithAmount() {
        let mockMessage = Message(
            id: "test-tx-id",
            sender: try! Account().address,
            recipient: try! Account().address,
            content: "Original message",
            timestamp: Date(),
            confirmedRound: 12345,
            direction: .received
        )

        let amount = MicroAlgos(250_000) // 0.25 ALGO
        let options = SendOptions.replying(to: mockMessage, amount: amount)

        #expect(options.amount == amount)
        #expect(options.replyContext != nil)
        #expect(options.replyContext?.messageId == "test-tx-id")
    }

    @Test("Replying without amount uses nil")
    func testReplyingWithoutAmount() {
        let mockMessage = Message(
            id: "test-tx-id",
            sender: try! Account().address,
            recipient: try! Account().address,
            content: "Original message",
            timestamp: Date(),
            confirmedRound: 12345,
            direction: .received
        )

        let options = SendOptions.replying(to: mockMessage)

        #expect(options.amount == nil)
        #expect(options.replyContext != nil)
    }
}

// MARK: - Localnet Integration Tests

@Suite("Custom Amount Localnet Integration Tests")
struct CustomAmountIntegrationTests {

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
            throw CustomAmountTestError.fundingFailed("Failed to list accounts")
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

        throw CustomAmountTestError.fundingFailed("No funded accounts found")
    }

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
            throw CustomAmountTestError.fundingFailed(output)
        }
    }

    private func waitForTransaction(from address: Address, algokit: AlgoKit, maxRetries: Int = 60) async throws {
        guard let indexer = await algokit.indexerClient else {
            throw CustomAmountTestError.indexerNotAvailable
        }

        for _ in 0..<maxRetries {
            let response = try await indexer.searchTransactions(address: address, limit: 10)
            for tx in response.transactions {
                if tx.sender == address.description,
                   let noteData = tx.noteData,
                   noteData.count > 2,
                   noteData[0] == 0x01 {
                    return
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw CustomAmountTestError.indexerTimeout
    }

    @Test("Send message with custom amount on localnet")
    func testSendWithCustomAmount() async throws {
        guard isLocalnetRunning() else {
            print("⚠️ Skipping test: localnet is not running. Start with `algokit localnet start`")
            return
        }

        print("\n" + String(repeating: "=", count: 60))
        print("🧪 CUSTOM AMOUNT TEST")
        print(String(repeating: "=", count: 60))

        // Create and fund accounts
        let alice = try Account()
        let bob = try Account()

        print("\n💰 Funding accounts...")
        try fundAccount(alice, amount: 10_000_000)
        try fundAccount(bob, amount: 10_000_000)
        print("   ✅ Accounts funded")

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create chat instances
        let aliceChat = try await AlgoChat(configuration: .localnet(), account: alice)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bob)

        // Get initial balances
        let aliceInitialBalance = try await aliceChat.balance()
        let bobInitialBalance = try await bobChat.balance()
        print("\n💵 Initial balances:")
        print("   Alice: \(Double(aliceInitialBalance.value) / 1_000_000) ALGO")
        print("   Bob:   \(Double(bobInitialBalance.value) / 1_000_000) ALGO")

        // Publish keys
        print("\n📤 Publishing keys...")
        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()
        print("   ✅ Keys published")

        // Wait for indexer
        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: alice.address, algokit: algokit)
        try await waitForTransaction(from: bob.address, algokit: algokit)

        // Send message with custom amount (0.5 ALGO = 500,000 microAlgos)
        let customAmount = MicroAlgos(500_000)
        print("\n📤 Sending message with \(Double(customAmount.value) / 1_000_000) ALGO...")

        let conv = try await aliceChat.conversation(with: bob.address)
        let result = try await aliceChat.send(
            "Hello with 0.5 ALGO!",
            to: conv,
            options: .withAmount(customAmount, confirmed: true)
        )
        print("   ✅ Message sent. TX: \(result.txid.prefix(12))...")

        // Verify Bob received the ALGO
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let bobFinalBalance = try await bobChat.balance()
        let bobReceived = bobFinalBalance.value - bobInitialBalance.value

        print("\n💵 Bob's balance change:")
        print("   Before: \(Double(bobInitialBalance.value) / 1_000_000) ALGO")
        print("   After:  \(Double(bobFinalBalance.value) / 1_000_000) ALGO")
        print("   Received: \(Double(bobReceived) / 1_000_000) ALGO")

        // Bob should have received the custom amount (minus any fees that apply to sender)
        // Note: Bob receives the full amount, Alice pays the fee
        #expect(bobReceived >= 400_000, "Bob should have received at least 0.4 ALGO (accounting for timing)")

        print("\n✅ Custom amount test passed!")
    }

    @Test("Send message with minimum amount on localnet")
    func testSendWithMinimumAmount() async throws {
        guard isLocalnetRunning() else {
            print("⚠️ Skipping test: localnet is not running")
            return
        }

        let alice = try Account()
        let bob = try Account()

        try fundAccount(alice, amount: 10_000_000)
        try fundAccount(bob, amount: 10_000_000)

        try await Task.sleep(nanoseconds: 2_000_000_000)

        let aliceChat = try await AlgoChat(configuration: .localnet(), account: alice)
        let bobChat = try await AlgoChat(configuration: .localnet(), account: bob)

        _ = try await aliceChat.publishKeyAndWait()
        _ = try await bobChat.publishKeyAndWait()

        let algokit = AlgoKit(configuration: .localnet())
        try await waitForTransaction(from: alice.address, algokit: algokit)
        try await waitForTransaction(from: bob.address, algokit: algokit)

        let bobInitialBalance = try await bobChat.balance()

        // Send with minimum amount (0.001 ALGO = 1000 microAlgos)
        let conv = try await aliceChat.conversation(with: bob.address)
        let result = try await aliceChat.send(
            "Hello with minimum amount!",
            to: conv,
            options: .withAmount(MessageTransaction.minimumPayment, confirmed: true)
        )

        #expect(!result.txid.isEmpty, "Should get transaction ID")

        try await Task.sleep(nanoseconds: 2_000_000_000)
        let bobFinalBalance = try await bobChat.balance()
        let bobReceived = bobFinalBalance.value - bobInitialBalance.value

        #expect(bobReceived >= 1000, "Bob should have received at least 1000 microAlgos")

        print("✅ Minimum amount test passed! Bob received \(bobReceived) microAlgos")
    }
}

// MARK: - Test Errors

private enum CustomAmountTestError: Error, LocalizedError {
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
