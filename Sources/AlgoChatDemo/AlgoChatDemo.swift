import AlgoChat
import Algorand
import AlgoKit
import CLI
import Foundation

@main
struct AlgoChatDemo {
    // Shared key storage for biometric access
    static let keyStorage = KeychainKeyStorage()

    static func main() async {
        let terminal = Terminal.shared

        // Show welcome banner
        await terminal.writeLine("""
        ┌─────────────────────────────────────────┐
        │   AlgoChat - Encrypted Blockchain Chat  │
        │         Powered by Algorand             │
        └─────────────────────────────────────────┘
        """.cyan)
        await terminal.writeLine("")

        // Check for biometric availability
        #if os(iOS) || os(macOS) || os(visionOS)
        let biometricType = KeychainKeyStorage.biometricType
        if biometricType != .none {
            await terminal.writeLine("🔐 \(biometricType.rawValue) available for secure key storage".dim)
            await terminal.writeLine("")
        }
        #endif

        // Main app loop
        var currentAccount: ChatAccount?
        var chat: AlgoChat?

        do {
        while true {
            if let account = currentAccount {
                // Logged in menu
                let shortAddr = String(account.address.description.prefix(8)) + "..."
                await terminal.writeLine("Logged in as: ".dim + shortAddr.green.bold)
                await terminal.writeLine("")

                let action = try await terminal.select(
                    "What would you like to do?",
                    options: [
                        "Send a message",
                        "Check messages",
                        "View conversations",
                        "Account info",
                        "Switch account",
                        "Exit"
                    ]
                )

                switch action {
                case "Send a message":
                    try await sendMessage(chat: chat!, terminal: terminal)
                case "Check messages":
                    try await checkMessages(chat: chat!, terminal: terminal)
                case "View conversations":
                    try await viewConversations(chat: chat!, terminal: terminal)
                case "Account info":
                    try await showAccountInfo(chat: chat!, account: account, terminal: terminal)
                case "Switch account":
                    currentAccount = nil
                    chat = nil
                    await terminal.writeLine("Logged out.".yellow)
                case "Exit":
                    await terminal.writeLine("Goodbye!".cyan)
                    return
                default:
                    break
                }
            } else {
                // Check for saved accounts
                let savedAddresses = try await keyStorage.listStoredAddresses()

                // Build menu options
                var options = [String]()

                // Add saved accounts first
                for addr in savedAddresses.prefix(3) {
                    let shortAddr = String(addr.description.prefix(8)) + "..."
                    #if os(iOS) || os(macOS) || os(visionOS)
                    let biometric = KeychainKeyStorage.biometricType.rawValue
                    options.append("🔐 \(shortAddr) (\(biometric))")
                    #else
                    options.append("🔐 \(shortAddr) (saved)")
                    #endif
                }

                options.append(contentsOf: [
                    "Generate new account",
                    "Load from mnemonic",
                    "Exit"
                ])

                let action = try await terminal.select(
                    "What would you like to do?",
                    options: options
                )

                if action.hasPrefix("🔐") {
                    // Extract address from the option
                    let addrStart = action.index(action.startIndex, offsetBy: 3)
                    let addrEnd = action.firstIndex(of: " ") ?? action.endIndex
                    let shortAddr = String(action[addrStart..<addrEnd])

                    // Find the full address
                    if let fullAddr = savedAddresses.first(where: {
                        $0.description.hasPrefix(shortAddr.replacingOccurrences(of: "...", with: ""))
                    }) {
                        if let account = await loadSavedAccount(address: fullAddr, terminal: terminal) {
                            currentAccount = account
                            chat = try await initChat(account: account, terminal: terminal)
                        }
                    }
                } else {
                    switch action {
                    case "Generate new account":
                        let account = try await generateAccount(terminal: terminal)
                        currentAccount = account
                        chat = try await initChat(account: account, terminal: terminal)

                        // Offer to save for biometric access
                        await offerToSaveKey(account: account, terminal: terminal)

                    case "Load from mnemonic":
                        if let account = try await loadAccount(terminal: terminal) {
                            currentAccount = account
                            chat = try await initChat(account: account, terminal: terminal)

                            // Offer to save for biometric access
                            await offerToSaveKey(account: account, terminal: terminal)
                        }

                    case "Exit":
                        await terminal.writeLine("Goodbye!".cyan)
                        return

                    default:
                        break
                    }
                }
            }

            await terminal.writeLine("")
        }
        } catch is TerminalError {
            // User pressed Ctrl+C - exit gracefully
            await terminal.writeLine("\nGoodbye!".cyan)
        } catch {
            await terminal.writeLine("\nError: \(error.localizedDescription)".red)
        }
    }

    // MARK: - Account Management

    static func loadSavedAccount(address: Address, terminal: Terminal) async -> ChatAccount? {
        await terminal.writeLine("")

        #if os(iOS) || os(macOS) || os(visionOS)
        let biometric = KeychainKeyStorage.biometricType.rawValue
        await terminal.writeLine("Authenticate with \(biometric) to unlock your encryption key...".dim)
        #endif

        do {
            // First, we need the mnemonic to get the Algorand account for signing
            // The biometric only protects the encryption key, not the signing key
            await terminal.writeLine("")
            await terminal.writeLine("Enter mnemonic for signing (encryption key is biometric-protected):".dim)

            let mnemonic = try await terminal.secret("Mnemonic")

            if mnemonic.isEmpty {
                await terminal.writeLine("Cancelled.".yellow)
                return nil
            }

            let algorandAccount = try Account(mnemonic: mnemonic)

            // Verify it matches the stored address
            guard algorandAccount.address == address else {
                await terminal.writeLine("Mnemonic doesn't match the stored account.".red)
                return nil
            }

            // Now retrieve the encryption key with biometric
            let account = try await terminal.withSpinner(
                message: "Authenticating",
                style: .dots
            ) {
                try await ChatAccount(account: algorandAccount, storage: keyStorage)
            }

            await terminal.writeLine("Account loaded with biometric-protected encryption key!".green)
            return account
        } catch KeyStorageError.biometricFailed {
            await terminal.writeLine("Biometric authentication failed or was cancelled.".red)
            return nil
        } catch KeyStorageError.keyNotFound {
            await terminal.writeLine("Encryption key not found. Please load from mnemonic.".red)
            return nil
        } catch {
            await terminal.writeLine("Failed to load account: \(error.localizedDescription)".red)
            return nil
        }
    }

    static func offerToSaveKey(account: ChatAccount, terminal: Terminal) async {
        #if os(iOS) || os(macOS) || os(visionOS)
        guard KeychainKeyStorage.biometricType != .none else { return }

        let biometric = KeychainKeyStorage.biometricType.rawValue

        await terminal.writeLine("")
        do {
            let save = try await terminal.select(
                "Save encryption key for \(biometric) access?",
                options: ["Yes, enable \(biometric)", "No, don't save"]
            )

            if save.hasPrefix("Yes") {
                try await account.saveEncryptionKey(to: keyStorage, requireBiometric: true)
                await terminal.writeLine("✅ Encryption key saved! You can now use \(biometric) to access your messages.".green)
            }
        } catch {
            await terminal.writeLine("Note: Could not save key - \(error.localizedDescription)".yellow)
        }
        #endif
    }

    static func generateAccount(terminal: Terminal) async throws -> ChatAccount {
        let account = try await terminal.withSpinner(
            message: "Generating new Algorand account",
            style: .dots
        ) {
            try ChatAccount()
        }

        await terminal.writeLine("")
        await terminal.writeLine("═══ NEW ACCOUNT CREATED ═══".green.bold)
        await terminal.writeLine("")
        await terminal.writeLine("Address:".dim)
        await terminal.writeLine("  \(account.address)".cyan)
        await terminal.writeLine("")
        await terminal.writeLine("Mnemonic (SAVE THIS!):".dim)
        await terminal.writeLine("  \(try account.account.mnemonic())".yellow)
        await terminal.writeLine("")
        await terminal.writeLine("Encryption Public Key:".dim)
        await terminal.writeLine("  \(account.publicKeyData.hexString)".magenta)
        await terminal.writeLine("")
        await terminal.writeLine("⚠️  Save your mnemonic phrase securely!".yellow.bold)
        await terminal.writeLine("")
        await terminal.writeLine("💰 Fund your account with TestNet ALGO:".dim)
        await terminal.writeLine("   https://bank.testnet.algorand.network/".blue.underline)
        await terminal.writeLine("")

        return account
    }

    static func loadAccount(terminal: Terminal) async throws -> ChatAccount? {
        await terminal.writeLine("")
        await terminal.writeLine("Enter your 25-word mnemonic phrase:".dim)

        let mnemonic = try await terminal.secret("Mnemonic")

        if mnemonic.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return nil
        }

        do {
            let account = try await terminal.withSpinner(
                message: "Loading account",
                style: .dots
            ) {
                try ChatAccount(mnemonic: mnemonic)
            }

            await terminal.writeLine("Account loaded: ".green + account.address.description.cyan)
            return account
        } catch {
            await terminal.writeLine("Failed to load account: \(error.localizedDescription)".red)
            return nil
        }
    }

    static func initChat(account: ChatAccount, terminal: Terminal) async throws -> AlgoChat {
        try await terminal.withSpinner(
            message: "Connecting to Algorand TestNet",
            style: .dots
        ) {
            try await AlgoChat(network: .testnet, account: account.account)
        }
    }

    // MARK: - Messaging

    static func sendMessage(chat: AlgoChat, terminal: Terminal) async throws {
        await terminal.writeLine("")

        let recipientStr = try await terminal.input("Recipient address")

        if recipientStr.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return
        }

        let recipient: Address
        do {
            recipient = try Address(string: recipientStr)
        } catch {
            await terminal.writeLine("Invalid address format.".red)
            return
        }

        let message = try await terminal.input("Your message")

        if message.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return
        }

        do {
            let txid = try await terminal.withSpinner(
                message: "Encrypting and sending message",
                style: .dots
            ) {
                try await chat.sendAndWait(message: message, to: recipient)
            }

            await terminal.writeLine("")
            await terminal.writeLine("✅ Message sent successfully!".green.bold)
            await terminal.writeLine("Transaction: ".dim + txid.cyan)
            await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(txid)".blue.underline)
        } catch ChatError.publicKeyNotFound {
            await terminal.writeLine("")
            await terminal.writeLine("⚠️  Recipient's encryption key not found.".yellow.bold)
            await terminal.writeLine("They need to send at least one message first".dim)
            await terminal.writeLine("so their public key is published on-chain.".dim)
        } catch {
            await terminal.writeLine("")
            await terminal.writeLine("❌ Failed to send: \(error.localizedDescription)".red)
        }
    }

    static func checkMessages(chat: AlgoChat, terminal: Terminal) async throws {
        await terminal.writeLine("")

        let fromStr = try await terminal.input("From address (or Enter for all)")

        if fromStr.isEmpty {
            // Show all conversations
            try await viewConversations(chat: chat, terminal: terminal)
            return
        }

        let from: Address
        do {
            from = try Address(string: fromStr)
        } catch {
            await terminal.writeLine("Invalid address format.".red)
            return
        }

        let messages = try await terminal.withSpinner(
            message: "Fetching messages",
            style: .dots
        ) {
            try await chat.fetchMessages(with: from)
        }

        await terminal.writeLine("")
        if messages.isEmpty {
            await terminal.writeLine("No messages found.".yellow)
        } else {
            await terminal.writeLine("═══ Messages ═══".cyan.bold)
            await terminal.writeLine("")
            for msg in messages {
                let arrow = msg.direction == .sent ? "→".green : "←".blue
                let time = formatDate(msg.timestamp)
                await terminal.writeLine("\(arrow) [\(time.dim)] \(msg.content)")
            }
        }
    }

    static func viewConversations(chat: AlgoChat, terminal: Terminal) async throws {
        let conversations = try await terminal.withSpinner(
            message: "Fetching conversations",
            style: .dots
        ) {
            try await chat.fetchConversations()
        }

        await terminal.writeLine("")
        if conversations.isEmpty {
            await terminal.writeLine("No conversations yet.".yellow)
            await terminal.writeLine("Send a message to start chatting!".dim)
        } else {
            await terminal.writeLine("═══ Conversations ═══".cyan.bold)
            await terminal.writeLine("")
            for conv in conversations {
                let shortAddr = String(conv.participant.description.prefix(12)) + "..."
                await terminal.writeLine("📱 \(shortAddr.cyan)")
                if let last = conv.lastMessage {
                    let who = last.direction == .sent ? "You" : "Them"
                    let preview = String(last.content.prefix(40))
                    await terminal.writeLine("   \(who.dim): \(preview)")
                }
                await terminal.writeLine("   Messages: \(conv.messages.count)".dim)
                await terminal.writeLine("")
            }
        }
    }

    // MARK: - Account Info

    static func showAccountInfo(chat: AlgoChat, account: ChatAccount, terminal: Terminal) async throws {
        await terminal.writeLine("")
        await terminal.writeLine("═══ Account Info ═══".cyan.bold)
        await terminal.writeLine("")

        let address = await chat.address
        let pubKey = await chat.publicKey

        await terminal.writeLine("Address:".dim)
        await terminal.writeLine("  \(address)".cyan)
        await terminal.writeLine("")
        await terminal.writeLine("Encryption Public Key:".dim)
        await terminal.writeLine("  \(pubKey.hexString)".magenta)
        await terminal.writeLine("")

        // Check if key is saved
        let hasSavedKey = await account.hasStoredEncryptionKey(in: keyStorage)
        if hasSavedKey {
            #if os(iOS) || os(macOS) || os(visionOS)
            let biometric = KeychainKeyStorage.biometricType.rawValue
            await terminal.writeLine("Key Storage:".dim)
            await terminal.writeLine("  🔐 Protected by \(biometric)".green)
            await terminal.writeLine("")
            #endif
        }

        do {
            let balance = try await terminal.withSpinner(
                message: "Fetching balance",
                style: .dots
            ) {
                try await chat.balance()
            }

            let algoAmount = Double(balance.value) / 1_000_000
            await terminal.writeLine("Balance:".dim)
            await terminal.writeLine("  \(String(format: "%.6f", algoAmount)) ALGO".green)
        } catch {
            await terminal.writeLine("Balance: ".dim + "Unable to fetch".red)
        }
    }

    // MARK: - Helpers

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
