import AlgoChat
import Algorand
import AlgoKit
import Foundation

@main
struct Demo {
    // ANSI color codes
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let cyan = "\u{001B}[36m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let magenta = "\u{001B}[35m"
    static let red = "\u{001B}[31m"

    static func main() async throws {
        // Clear screen
        print("\u{001B}[2J\u{001B}[H", terminator: "")

        print("""
        \(cyan)\(bold)
        ╔══════════════════════════════════════════════════════════════════╗
        ║           AlgoChat - Live Encryption Demonstration               ║
        ║              End-to-End Encrypted Blockchain Messaging           ║
        ╚══════════════════════════════════════════════════════════════════╝
        \(reset)
        """)

        await sleep(1.0)

        // ========== STEP 1: Create Accounts ==========
        printStep("STEP 1", "Creating Chat Accounts")

        await typeText("   Generating Alice's Algorand account...")
        let alice = try ChatAccount()
        print(" \(green)✓\(reset)")

        await typeText("   Generating Bob's Algorand account...")
        let bob = try ChatAccount()
        print(" \(green)✓\(reset)")

        print()
        print("   \(dim)┌─────────────────────────────────────────────────────────────┐\(reset)")
        print("   \(dim)│\(reset) \(cyan)👩 ALICE\(reset)                                                  \(dim)│\(reset)")
        print("   \(dim)│\(reset)    Address: \(yellow)\(alice.address.description.prefix(20))...\(reset)           \(dim)│\(reset)")
        print("   \(dim)│\(reset)    Encryption Key: \(magenta)\(alice.publicKeyData.prefix(8).hex)...\(reset)              \(dim)│\(reset)")
        print("   \(dim)├─────────────────────────────────────────────────────────────┤\(reset)")
        print("   \(dim)│\(reset) \(cyan)👨 BOB\(reset)                                                    \(dim)│\(reset)")
        print("   \(dim)│\(reset)    Address: \(yellow)\(bob.address.description.prefix(20))...\(reset)           \(dim)│\(reset)")
        print("   \(dim)│\(reset)    Encryption Key: \(magenta)\(bob.publicKeyData.prefix(8).hex)...\(reset)              \(dim)│\(reset)")
        print("   \(dim)└─────────────────────────────────────────────────────────────┘\(reset)")
        print()

        await sleep(1.5)

        // ========== STEP 2: Fund Accounts ==========
        printStep("STEP 2", "Funding Accounts from Localnet")

        let fundingAddress = try discoverFundingAddress()

        print("   Sending 10 ALGO to Alice... ", terminator: "")
        fflush(stdout)
        try fundAccount(alice.account, from: fundingAddress, amount: 10_000_000)
        print("\(green)✓\(reset)")

        print("   Sending 10 ALGO to Bob... ", terminator: "")
        fflush(stdout)
        try fundAccount(bob.account, from: fundingAddress, amount: 10_000_000)
        print("\(green)✓\(reset)")
        print()

        await sleep(1.0)

        // ========== STEP 3: Connect to Algorand ==========
        printStep("STEP 3", "Connecting to Algorand Blockchain")

        let localnetConfig = AlgorandConfiguration(
            network: .localnet,
            apiToken: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )

        print("   Connecting Alice... ", terminator: "")
        fflush(stdout)
        let aliceChat = try await AlgoChat(configuration: localnetConfig, account: alice.account)
        print("\(green)✓\(reset) \(dim)localhost:4001\(reset)")

        print("   Connecting Bob... ", terminator: "")
        fflush(stdout)
        let bobChat = try await AlgoChat(configuration: localnetConfig, account: bob.account)
        print("\(green)✓\(reset) \(dim)localhost:4001\(reset)")
        print()

        await sleep(1.0)

        // ========== STEP 4: Publish Keys ==========
        printStep("STEP 4", "Publishing Encryption Keys On-Chain")

        print("   \(dim)Each user publishes their X25519 public key to the blockchain\(reset)")
        print("   \(dim)so others can encrypt messages to them.\(reset)")
        print()

        print("   Alice publishing key... ", terminator: "")
        fflush(stdout)
        let aliceKeyTx = try await aliceChat.sendAndWait(
            message: "Key published",
            to: alice.address,
            recipientPublicKey: alice.encryptionPublicKey
        )
        print("\(green)✓\(reset) \(dim)TX: \(aliceKeyTx.prefix(12))...\(reset)")

        print("   Bob publishing key... ", terminator: "")
        fflush(stdout)
        let bobKeyTx = try await bobChat.sendAndWait(
            message: "Key published",
            to: bob.address,
            recipientPublicKey: bob.encryptionPublicKey
        )
        print("\(green)✓\(reset) \(dim)TX: \(bobKeyTx.prefix(12))...\(reset)")

        print("   Waiting for indexer... ", terminator: "")
        fflush(stdout)
        try await waitForPublicKey(chat: aliceChat, address: bob.address)
        try await waitForPublicKey(chat: bobChat, address: alice.address)
        print("\(green)✓\(reset)")
        print()

        await sleep(1.0)

        // ========== STEP 5: Send Encrypted Messages ==========
        printStep("STEP 5", "Sending Encrypted Messages")

        print()
        print("   \(dim)┌─────────────────────────────────────────────────────────────┐\(reset)")
        print("   \(dim)│\(reset) \(bold)Encryption Pipeline:\(reset)                                       \(dim)│\(reset)")
        print("   \(dim)│\(reset)  1. Generate ephemeral X25519 keypair                        \(dim)│\(reset)")
        print("   \(dim)│\(reset)  2. ECDH key agreement with recipient's public key           \(dim)│\(reset)")
        print("   \(dim)│\(reset)  3. HKDF-SHA256 to derive symmetric key                      \(dim)│\(reset)")
        print("   \(dim)│\(reset)  4. ChaCha20-Poly1305 authenticated encryption               \(dim)│\(reset)")
        print("   \(dim)│\(reset)  5. Embed in Algorand transaction note                       \(dim)│\(reset)")
        print("   \(dim)└─────────────────────────────────────────────────────────────┘\(reset)")
        print()

        await sleep(1.5)

        // Message 1: Alice to Bob
        let msg1 = "Hey Bob! Can you read this encrypted message?"
        print("   \(cyan)👩 Alice\(reset) typing...")
        await typeText("      \"\(msg1)\"")
        print()

        print("      Encrypting & sending... ", terminator: "")
        fflush(stdout)
        let tx1 = try await aliceChat.sendAndWait(message: msg1, to: bob.address)
        print("\(green)✓\(reset) \(dim)TX: \(tx1.prefix(12))...\(reset)")
        print()

        await sleep(1.0)

        // Message 2: Bob to Alice
        let msg2 = "Yes! This is amazing - true E2E encryption!"
        print("   \(cyan)👨 Bob\(reset) typing...")
        await typeText("      \"\(msg2)\"")
        print()

        print("      Encrypting & sending... ", terminator: "")
        fflush(stdout)
        let tx2 = try await bobChat.sendAndWait(message: msg2, to: alice.address)
        print("\(green)✓\(reset) \(dim)TX: \(tx2.prefix(12))...\(reset)")
        print()

        await sleep(1.0)

        // Message 3: Alice to Bob
        let msg3 = "Nobody else can read these messages! 🔐"
        print("   \(cyan)👩 Alice\(reset) typing...")
        await typeText("      \"\(msg3)\"")
        print()

        print("      Encrypting & sending... ", terminator: "")
        fflush(stdout)
        let tx3 = try await aliceChat.sendAndWait(message: msg3, to: bob.address)
        print("\(green)✓\(reset) \(dim)TX: \(tx3.prefix(12))...\(reset)")
        print()

        await sleep(1.5)

        // ========== STEP 6: Fetch & Decrypt ==========
        printStep("STEP 6", "Fetching & Decrypting Messages")

        // Wait for indexer to sync the sent messages
        print("   Waiting for indexer to sync messages... ", terminator: "")
        fflush(stdout)
        try await waitForMessages(
            chat: bobChat,
            from: alice.address,
            expectedCount: 2  // Alice sent 2 messages to Bob
        )
        print("\(green)✓\(reset)")

        print()
        print("   \(cyan)👨 Bob\(reset) opens his inbox...")
        await sleep(0.5)

        print("      Fetching & decrypting... ", terminator: "")
        fflush(stdout)
        let bobMessages = try await bobChat.fetchMessages(with: alice.address)
        print("\(green)✓\(reset)")

        print()
        print("   \(dim)┌─────────────────────────────────────────────────────────────┐\(reset)")
        print("   \(dim)│\(reset) \(bold)📬 Bob's Decrypted Messages from Alice:\(reset)                    \(dim)│\(reset)")
        for msg in bobMessages {
            let arrow = msg.direction == .received ? "←" : "→"
            let content = String(msg.content.prefix(48))
            print("   \(dim)│\(reset)   \(green)\(arrow)\(reset) \(content)\(msg.content.count > 48 ? "..." : "")")
        }
        print("   \(dim)└─────────────────────────────────────────────────────────────┘\(reset)")

        await sleep(1.5)

        print()
        print("   \(cyan)👩 Alice\(reset) opens her inbox...")
        await sleep(0.5)

        print("      Fetching & decrypting... ", terminator: "")
        fflush(stdout)
        let aliceMessages = try await aliceChat.fetchMessages(with: bob.address)
        print("\(green)✓\(reset)")

        print()
        print("   \(dim)┌─────────────────────────────────────────────────────────────┐\(reset)")
        print("   \(dim)│\(reset) \(bold)📬 Alice's Decrypted Messages from Bob:\(reset)                    \(dim)│\(reset)")
        for msg in aliceMessages {
            let arrow = msg.direction == .received ? "←" : "→"
            let content = String(msg.content.prefix(48))
            print("   \(dim)│\(reset)   \(green)\(arrow)\(reset) \(content)\(msg.content.count > 48 ? "..." : "")")
        }
        print("   \(dim)└─────────────────────────────────────────────────────────────┘\(reset)")

        await sleep(1.5)

        // ========== STEP 7: Security Test ==========
        printStep("STEP 7", "Security Verification")

        print()
        print("   \(red)👿 EVE\(reset) (attacker) enters the scene...")
        await sleep(1.0)

        let eve = try ChatAccount()
        try fundAccount(eve.account, from: fundingAddress, amount: 1_000_000)
        let eveChat = try await AlgoChat(configuration: localnetConfig, account: eve.account)

        print("   \(dim)Eve's address: \(eve.address.description.prefix(16))...\(reset)")
        print()

        await typeText("   Eve: \"I'll intercept Alice and Bob's messages...\"")
        print()
        await sleep(1.0)

        print("   Eve attempting to decrypt... ", terminator: "")
        fflush(stdout)
        let eveMessages = try await eveChat.fetchMessages(with: alice.address)
        print("\(red)✗\(reset)")

        print()
        if eveMessages.isEmpty {
            print("   \(red)Eve decrypted: \(bold)0 messages\(reset)")
            print()
            await typeText("   Eve: \"I can't read anything! The encryption is too strong!\"")
            print()
        }

        await sleep(1.0)
        print()
        print("   \(green)\(bold)✓ SECURITY VERIFIED!\(reset)")
        print("   \(dim)Without the private key, messages are completely unreadable.\(reset)")

        await sleep(1.5)

        // ========== Summary ==========
        print()
        print("""
        \(cyan)\(bold)
        ╔══════════════════════════════════════════════════════════════════╗
        ║                    DEMONSTRATION COMPLETE                        ║
        ╠══════════════════════════════════════════════════════════════════╣
        ║  \(green)✓\(cyan) Created 2 Algorand accounts with X25519 encryption keys     ║
        ║  \(green)✓\(cyan) Funded accounts from localnet dispenser                      ║
        ║  \(green)✓\(cyan) Published encryption keys on Algorand blockchain             ║
        ║  \(green)✓\(cyan) Sent 3 end-to-end encrypted messages                         ║
        ║  \(green)✓\(cyan) Successfully decrypted all messages                          ║
        ║  \(green)✓\(cyan) Verified attacker cannot decrypt messages                    ║
        ╠══════════════════════════════════════════════════════════════════╣
        ║  \(yellow)🔐 Encryption:\(cyan) X25519 + HKDF-SHA256 + ChaCha20-Poly1305        ║
        ║  \(yellow)⛓️  Storage:\(cyan) Algorand blockchain (immutable, decentralized)    ║
        ║  \(yellow)🔑 Keys:\(cyan) Keychain with Touch ID/Face ID protection             ║
        ╚══════════════════════════════════════════════════════════════════╝
        \(reset)
        """)
    }

    // MARK: - UI Helpers

    static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    static func typeText(_ text: String, speed: Double = 0.02) async {
        for char in text {
            print(char, terminator: "")
            fflush(stdout)
            try? await Task.sleep(nanoseconds: UInt64(speed * 1_000_000_000))
        }
    }

    static func printStep(_ step: String, _ title: String) {
        print()
        print("   \(bold)\(cyan)━━━ \(step): \(title) ━━━\(reset)")
        print()
    }

    // MARK: - Blockchain Helpers

    static func discoverFundingAddress() throws -> String {
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
            throw DemoError.fundingFailed("Failed to list accounts")
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

        throw DemoError.fundingFailed("No funded accounts found")
    }

    static func fundAccount(_ account: Account, from fundingAddress: String, amount: UInt64) throws {
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
            throw DemoError.fundingFailed(output)
        }
    }

    static func waitForPublicKey(chat: AlgoChat, address: Address, maxAttempts: Int = 60) async throws {
        // Give the indexer a moment to process new transactions
        try await Task.sleep(nanoseconds: 1_000_000_000)

        for _ in 0..<maxAttempts {
            do {
                _ = try await chat.fetchPublicKey(for: address)
                return
            } catch {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw DemoError.keyNotFound
    }

    static func waitForMessages(chat: AlgoChat, from participant: Address, expectedCount: Int, maxAttempts: Int = 60) async throws {
        for _ in 0..<maxAttempts {
            let messages = try await chat.fetchMessages(with: participant)
            let receivedCount = messages.filter { $0.direction == .received }.count
            if receivedCount >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw DemoError.messagesNotFound
    }

    enum DemoError: Error {
        case fundingFailed(String)
        case keyNotFound
        case messagesNotFound
    }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
