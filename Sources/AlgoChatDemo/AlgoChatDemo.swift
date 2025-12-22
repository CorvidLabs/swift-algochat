import AlgoChat
import Algorand
import AlgoKit
import CLI
import Foundation

@main
struct AlgoChatDemo {
    // Shared key storage for biometric access
    static let keyStorage = KeychainKeyStorage()

    // Selected network (set at startup)
    nonisolated(unsafe) static var isLocalnet: Bool = true

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
        // Network selection
        let networkChoice = try await terminal.select(
            "Select network",
            options: [
                "Localnet (local development)",
                "TestNet (public test network)"
            ]
        )
        isLocalnet = networkChoice.contains("Localnet")
        let networkName = isLocalnet ? "Localnet" : "TestNet"
        await terminal.writeLine("Network: \(networkName)".green)
        await terminal.writeLine("")

        while true {
            if let account = currentAccount {
                // Logged in menu
                let shortAddr = String(account.address.description.prefix(8)) + "..."
                let networkLabel = isLocalnet ? "Localnet" : "TestNet"
                await terminal.writeLine("Logged in as: ".dim + shortAddr.green.bold + " on ".dim + networkLabel.cyan)
                await terminal.writeLine("")

                var menuOptions = [
                    "Send a message",
                    "Check messages",
                    "View conversations",
                    "Publish encryption key",
                    "Account info"
                ]

                // Only show fund option on localnet
                if isLocalnet {
                    menuOptions.append("Fund account")
                }

                menuOptions.append(contentsOf: ["Switch account", "Exit"])

                let action = try await terminal.select(
                    "What would you like to do?",
                    options: menuOptions
                )

                switch action {
                case "Send a message":
                    try await sendMessage(chat: chat!, terminal: terminal)
                case "Check messages":
                    try await checkMessages(chat: chat!, terminal: terminal)
                case "View conversations":
                    try await viewConversations(chat: chat!, terminal: terminal)
                case "Publish encryption key":
                    try await publishEncryptionKey(chat: chat!, terminal: terminal)
                case "Account info":
                    try await showAccountInfo(chat: chat!, account: account, terminal: terminal)
                case "Fund account":
                    await fundAccount(address: account.address, terminal: terminal)
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
        if isLocalnet {
            await terminal.writeLine("💰 Fund your account using the menu option.".dim)
        } else {
            await terminal.writeLine("💰 Fund your account with TestNet ALGO:".dim)
            await terminal.writeLine("   https://bank.testnet.algorand.network/".blue.underline)
        }
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
        let networkName = isLocalnet ? "Localnet" : "TestNet"
        return try await terminal.withSpinner(
            message: "Connecting to Algorand \(networkName)",
            style: .dots
        ) {
            if isLocalnet {
                let config = AlgorandConfiguration(
                    network: .localnet,
                    apiToken: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                )
                return try await AlgoChat(configuration: config, account: account.account)
            } else {
                return try await AlgoChat(network: .testnet, account: account.account)
            }
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
            if !isLocalnet {
                await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(txid)".blue.underline)
            }
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

        try await viewConversation(chat: chat, participant: from, terminal: terminal)
    }

    static func viewConversation(chat: AlgoChat, participant: Address, terminal: Terminal) async throws {
        var allMessages: [Message] = []

        // Initial load
        let messages = try await terminal.withSpinner(
            message: "Fetching messages",
            style: .dots
        ) {
            try await chat.fetchMessages(with: participant)
        }
        allMessages = messages

        while true {
            await terminal.writeLine("")

            if allMessages.isEmpty {
                await terminal.writeLine("No messages yet.".yellow)
            } else {
                let shortAddr = String(participant.description.prefix(12)) + "..."
                let networkLabel = isLocalnet ? "[Localnet]".yellow : "[TestNet]".cyan
                await terminal.writeLine("═══ Conversation with \(shortAddr.cyan) ═══ \(networkLabel)".bold)
                await terminal.writeLine("")

                // Display messages with improved formatting
                for msg in allMessages {
                    let time = formatRelativeTime(msg.timestamp)

                    if msg.direction == .sent {
                        // Sent message - right-aligned style
                        await terminal.writeLine("                              \(time.dim)")
                        // Show reply indicator BEFORE the message if this is a reply
                        if let preview = msg.replyToPreview {
                            let truncated = preview.count > 30 ? String(preview.prefix(27)) + "..." : preview
                            await terminal.writeLine("                    " + "↳ \"\(truncated)\"".dim)
                        }
                        await terminal.writeLine("                    \(msg.content)".green + " [You]".dim)
                    } else {
                        // Received message - left-aligned style
                        await terminal.writeLine("\(time.dim)")
                        // Show reply indicator BEFORE the message if this is a reply
                        if let preview = msg.replyToPreview {
                            let truncated = preview.count > 30 ? String(preview.prefix(27)) + "..." : preview
                            await terminal.writeLine("↳ \"\(truncated)\"".dim)
                        }
                        await terminal.writeLine("[Them] ".dim + msg.content.blue)
                    }

                    await terminal.writeLine("")
                }
            }

            // Show action menu
            let lastReceived = allMessages.last { $0.direction == .received }
            var options = ["Send new message"]

            if lastReceived != nil {
                options.insert("Reply to last message", at: 0)
            }

            options.append(contentsOf: ["Refresh", "Back"])

            let action = try await terminal.select(
                "Actions",
                options: options
            )

            switch action {
            case "Reply to last message":
                if let original = lastReceived {
                    try await sendReply(chat: chat, to: participant, replyingTo: original, terminal: terminal)
                    // Refresh messages after sending
                    allMessages = try await chat.fetchMessages(with: participant)
                }
            case "Send new message":
                try await sendMessageTo(chat: chat, recipient: participant, terminal: terminal)
                // Refresh messages after sending
                allMessages = try await chat.fetchMessages(with: participant)
            case "Refresh":
                allMessages = try await terminal.withSpinner(
                    message: "Refreshing",
                    style: .dots
                ) {
                    try await chat.fetchMessages(with: participant)
                }
            case "Back":
                return
            default:
                break
            }
        }
    }

    static func sendMessageTo(chat: AlgoChat, recipient: Address, terminal: Terminal) async throws {
        let message = try await terminal.input("Your message")

        if message.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return
        }

        do {
            let txid = try await terminal.withSpinner(
                message: "Sending",
                style: .dots
            ) {
                try await chat.sendAndWait(message: message, to: recipient)
            }

            await terminal.writeLine("✅ Sent!".green + " TX: \(String(txid.prefix(12)))...".dim)
            if !isLocalnet {
                await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(txid)".blue.underline)
            }
        } catch {
            await terminal.writeLine("❌ Failed: \(error.localizedDescription)".red)
        }
    }

    static func sendReply(
        chat: AlgoChat,
        to recipient: Address,
        replyingTo original: Message,
        terminal: Terminal
    ) async throws {
        await terminal.writeLine("")
        let preview = original.content.count > 50
            ? String(original.content.prefix(47)) + "..."
            : original.content
        await terminal.writeLine("Replying to: ".dim + "\"\(preview)\"".cyan)

        let reply = try await terminal.input("Your reply")

        if reply.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return
        }

        do {
            let txid = try await terminal.withSpinner(
                message: "Sending reply",
                style: .dots
            ) {
                try await chat.sendReplyAndWait(message: reply, to: recipient, replyingTo: original)
            }

            await terminal.writeLine("✅ Reply sent!".green + " TX: \(String(txid.prefix(12)))...".dim)
            if !isLocalnet {
                await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(txid)".blue.underline)
            }
        } catch {
            await terminal.writeLine("❌ Failed: \(error.localizedDescription)".red)
        }
    }

    static func publishEncryptionKey(chat: AlgoChat, terminal: Terminal) async throws {
        await terminal.writeLine("")
        await terminal.writeLine("Publishing your encryption key allows others to message you".dim)
        await terminal.writeLine("even before you've sent them a message.".dim)
        await terminal.writeLine("")

        do {
            let txid = try await terminal.withSpinner(
                message: "Publishing encryption key",
                style: .dots
            ) {
                try await chat.publishKeyAndWait()
            }

            await terminal.writeLine("")
            await terminal.writeLine("Key published successfully!".green.bold)
            await terminal.writeLine("Transaction: ".dim + txid.cyan)
            if !isLocalnet {
                await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(txid)".blue.underline)
            }
        } catch {
            await terminal.writeLine("")
            await terminal.writeLine("Failed to publish key: \(error.localizedDescription)".red)
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
            let networkLabel = isLocalnet ? "[Localnet]".yellow : "[TestNet]".cyan
            await terminal.writeLine("═══ Conversations ═══ \(networkLabel)".cyan.bold)
            await terminal.writeLine("")

            // Build options for selection
            var options: [String] = []
            for conv in conversations {
                let shortAddr = String(conv.participant.description.prefix(12)) + "..."
                if let last = conv.lastMessage {
                    let time = formatRelativeTime(last.timestamp)
                    let who = last.direction == .sent ? "You" : "Them"
                    let preview = String(last.content.prefix(30))
                    options.append("📱 \(shortAddr) (\(conv.messages.count) msgs) - \(who): \(preview)... [\(time)]")
                } else {
                    options.append("📱 \(shortAddr) (\(conv.messages.count) msgs)")
                }
            }
            options.append("Back")

            let selection = try await terminal.select(
                "Select a conversation",
                options: options
            )

            if selection == "Back" {
                return
            }

            // Find the selected conversation
            if let index = options.firstIndex(of: selection), index < conversations.count {
                let conv = conversations[index]
                try await viewConversation(chat: chat, participant: conv.participant, terminal: terminal)
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

    // MARK: - Localnet Funding

    /// Discovers a funded address from the localnet KMD wallet
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FundingError.failed("Docker/localnet error: \(output)")
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

        throw FundingError.failed("No funded accounts found in localnet wallet")
    }

    /// Funds an account on localnet using goal CLI (10 ALGO)
    static func fundAccount(address: Address, terminal: Terminal) async {
        await terminal.writeLine("")

        do {
            let fundingAddress = try await terminal.withSpinner(
                message: "Finding localnet dispenser",
                style: .dots
            ) {
                try discoverFundingAddress()
            }

            try await terminal.withSpinner(
                message: "Sending 10 ALGO",
                style: .dots
            ) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/docker")
                task.arguments = [
                    "exec", "algokit_sandbox_algod",
                    "goal", "clerk", "send",
                    "-a", "10000000",  // 10 ALGO in microAlgos
                    "-f", fundingAddress,
                    "-t", address.description,
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
                    throw FundingError.failed(output)
                }
            }

            await terminal.writeLine("")
            await terminal.writeLine("✅ Funded with 10 ALGO!".green.bold)
            await terminal.writeLine("You can now send messages.".dim)
        } catch FundingError.failed(let message) {
            await terminal.writeLine("")
            await terminal.writeLine("❌ Funding failed".red.bold)
            await terminal.writeLine("Make sure localnet is running: ".dim + "algokit localnet start".yellow)
            await terminal.writeLine("Error: \(message)".dim)
        } catch {
            await terminal.writeLine("")
            await terminal.writeLine("❌ Funding failed: \(error.localizedDescription)".red)
        }
    }

    // MARK: - Helpers

    static func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        switch interval {
        case ..<60:
            return "just now"
        case ..<3600:
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        case ..<86400:
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        case ..<172800:
            return "yesterday"
        case ..<604800:
            let days = Int(interval / 86400)
            return "\(days)d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

enum FundingError: Error {
    case failed(String)
}
