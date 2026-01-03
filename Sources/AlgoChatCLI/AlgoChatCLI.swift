import AlgoChat
import Algorand
import AlgoKit
import CLI
import Foundation

@main
struct AlgoChatCLI {
    // MARK: - Constants

    /// Maximum message size in bytes (transaction note limit minus envelope overhead)
    static let maxMessageBytes = 962

    /// Standard address display length
    static let addressDisplayLength = 12

    /// Standard preview display length
    static let previewDisplayLength = 30

    /// Auto-refresh interval in seconds
    static let autoRefreshInterval: UInt64 = 10

    // MARK: - State

    /// Shared key storage (Keychain on Apple platforms, file-based on Linux)
    #if os(iOS) || os(macOS) || os(visionOS)
    static let keyStorage = KeychainKeyStorage()
    #else
    static let fileKeyStorage = FileKeyStorage()
    #endif

    /// Selected network (set at startup)
    nonisolated(unsafe) static var isLocalnet: Bool = true

    /// Whether we're running on Linux
    static var isLinux: Bool {
        #if os(Linux)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Cross-Platform Key Storage Helpers

    /// Lists stored addresses from the appropriate storage
    static func listStoredAddresses() async throws -> [Address] {
        #if os(iOS) || os(macOS) || os(visionOS)
        return try await keyStorage.listStoredAddresses()
        #else
        return try await fileKeyStorage.listStoredAddresses()
        #endif
    }

    /// Checks if a key exists for an address
    static func hasStoredKey(for address: Address) async -> Bool {
        #if os(iOS) || os(macOS) || os(visionOS)
        return await keyStorage.hasKey(for: address)
        #else
        return await fileKeyStorage.hasKey(for: address)
        #endif
    }

    /// Prompts for password on Linux (required for file storage)
    static func promptForStoragePassword(terminal: Terminal, forSaving: Bool = false) async throws -> String? {
        #if os(Linux)
        if forSaving {
            await terminal.writeLine("")
            await terminal.writeLine("Create a password to encrypt your keys:".dim)
            let password = try await terminal.secret("Password")
            if password.isEmpty {
                return nil
            }
            let confirm = try await terminal.secret("Confirm password")
            if password != confirm {
                await terminal.writeLine("Passwords don't match.".red)
                return nil
            }
            await fileKeyStorage.setPassword(password)
            return password
        } else {
            await terminal.writeLine("")
            await terminal.writeLine("Enter password to unlock your keys:".dim)
            let password = try await terminal.secret("Password")
            if password.isEmpty {
                return nil
            }
            await fileKeyStorage.setPassword(password)
            return password
        }
        #else
        return nil  // Not needed on Apple platforms
        #endif
    }

    /// Network display name
    static var networkName: String {
        isLocalnet ? "Localnet" : "TestNet"
    }

    // MARK: - Helper Functions

    /// Truncates an address for display
    static func truncateAddress(_ address: String, length: Int = addressDisplayLength) -> String {
        if address.count <= length + 3 {
            return address
        }
        return String(address.prefix(length)) + "..."
    }

    /// Truncates a message preview for display
    static func truncatePreview(_ text: String, length: Int = previewDisplayLength) -> String {
        if text.count <= length {
            return text
        }
        return String(text.prefix(length - 3)) + "..."
    }

    /// Finds Docker executable path
    static func findDockerPath() -> String? {
        // Common Docker paths across platforms
        let paths = [
            "/opt/homebrew/bin/docker",   // Apple Silicon Homebrew
            "/usr/local/bin/docker",      // Intel Homebrew / standard macOS
            "/usr/bin/docker",            // Linux system install
            "/snap/bin/docker",           // Ubuntu Snap install
            "/usr/bin/podman"             // Podman (Docker alternative on Linux)
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fallback: try 'which docker' on Unix systems
        #if os(Linux) || os(macOS)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["docker"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // which failed, return nil
        }
        #endif

        return nil
    }

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

        // Check for key storage availability
        #if os(iOS) || os(macOS) || os(visionOS)
        let biometricType = KeychainKeyStorage.biometricType
        if biometricType != .none {
            await terminal.writeLine("🔐 \(biometricType.rawValue) available for secure key storage".dim)
            await terminal.writeLine("")
        }
        #else
        await terminal.writeLine("🔐 Password-protected key storage available (~/.algochat/keys/)".dim)
        await terminal.writeLine("")
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
                let shortAddr = truncateAddress(account.address.description)
                await terminal.writeLine("Logged in as: ".dim + shortAddr.green.bold + " on ".dim + networkName.cyan)
                await terminal.writeLine("")

                var menuOptions = [
                    "View conversations",
                    "Send a message",
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
                case "View conversations":
                    try await viewConversations(chat: chat!, terminal: terminal)
                case "Send a message":
                    try await sendMessage(chat: chat!, terminal: terminal)
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
                let savedAddresses = try await listStoredAddresses()

                // Build menu options
                var options = [String]()

                // Add saved accounts first
                for addr in savedAddresses.prefix(3) {
                    let shortAddr = truncateAddress(addr.description)
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
        #else
        // On Linux, prompt for password first
        guard let _ = try? await promptForStoragePassword(terminal: terminal, forSaving: false) else {
            await terminal.writeLine("Cancelled.".yellow)
            return nil
        }
        #endif

        do {
            // First, we need the mnemonic to get the Algorand account for signing
            // The biometric/password only protects the encryption key, not the signing key
            await terminal.writeLine("")
            #if os(iOS) || os(macOS) || os(visionOS)
            await terminal.writeLine("Enter mnemonic for signing (encryption key is biometric-protected):".dim)
            #else
            await terminal.writeLine("Enter mnemonic for signing (encryption key is password-protected):".dim)
            #endif

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

            // Now retrieve the encryption key
            let account = try await terminal.withSpinner(
                message: "Authenticating",
                style: .dots
            ) {
                #if os(iOS) || os(macOS) || os(visionOS)
                try await ChatAccount(account: algorandAccount, storage: keyStorage)
                #else
                try await ChatAccount(account: algorandAccount, storage: fileKeyStorage)
                #endif
            }

            await terminal.writeLine("Account loaded with protected encryption key!".green)
            return account
        } catch KeyStorageError.biometricFailed {
            await terminal.writeLine("Biometric authentication failed or was cancelled.".red)
            return nil
        } catch KeyStorageError.decryptionFailed {
            await terminal.writeLine("Incorrect password.".red)
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
        #else
        // On Linux, offer password-protected file storage
        await terminal.writeLine("")
        do {
            let save = try await terminal.select(
                "Save encryption key with password protection?",
                options: ["Yes, save with password", "No, don't save"]
            )

            if save.hasPrefix("Yes") {
                guard let _ = try await promptForStoragePassword(terminal: terminal, forSaving: true) else {
                    return
                }
                try await account.saveEncryptionKey(to: fileKeyStorage, requireBiometric: false)
                await terminal.writeLine("✅ Encryption key saved to ~/.algochat/keys/".green)
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

        // Validate word count
        let words = mnemonic.split(separator: " ").filter { !$0.isEmpty }
        if words.count != 25 {
            await terminal.writeLine("Invalid mnemonic: expected 25 words, got \(words.count).".red)
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

        let message = try await terminal.input("Your message (max \(maxMessageBytes) bytes)")

        if message.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return
        }

        // Validate message size
        let messageBytes = message.utf8.count
        if messageBytes > maxMessageBytes {
            await terminal.writeLine("Message too large: \(messageBytes) bytes (max \(maxMessageBytes)).".red)
            return
        }

        do {
            // Use .indexed for self-messages to ensure they appear immediately
            let myAddress = await chat.address
            let isSelfMessage = recipient == myAddress
            let sendOptions: SendOptions = isSelfMessage ? .indexed : .confirmed
            let spinnerMessage = isSelfMessage
                ? "Encrypting and sending message (waiting for indexer)"
                : "Encrypting and sending message"

            let result = try await terminal.withSpinner(
                message: spinnerMessage,
                style: .dots
            ) {
                try await chat.send(message, to: recipient, options: sendOptions)
            }

            await terminal.writeLine("")
            await terminal.writeLine("✅ Message sent successfully!".green.bold)
            await terminal.writeLine("Transaction: ".dim + result.txid.cyan)
            if !isLocalnet {
                await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(result.txid)".blue.underline)
            }

            // Navigate to conversation with the sent message
            try await viewConversation(
                chat: chat,
                participant: recipient,
                terminal: terminal,
                initialMessage: result.message
            )
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

    static func viewConversation(
        chat: AlgoChat,
        participant: Address,
        terminal: Terminal,
        initialMessage: Message? = nil
    ) async throws {
        // Initial load using conversation-first API
        var conversation = try await terminal.withSpinner(
            message: "Fetching messages",
            style: .dots
        ) {
            var conv = try await chat.conversation(with: participant)
            conv = try await chat.refresh(conv)
            return conv
        }

        // Merge initial message if provided (handles indexer latency)
        if let msg = initialMessage {
            conversation.append(msg)
        }

        var autoRefreshEnabled = false
        var lastRefreshTime = Date()

        while true {
            // Auto-refresh if enabled
            if autoRefreshEnabled {
                let currentConv = conversation
                conversation = (try? await chat.refresh(currentConv)) ?? currentConv
                lastRefreshTime = Date()
            }

            await terminal.writeLine("")

            if conversation.isEmpty {
                await terminal.writeLine("No messages yet.".yellow)
            } else {
                let shortAddr = truncateAddress(participant.description)
                let networkLabel = isLocalnet ? "[Localnet]".yellow : "[TestNet]".cyan
                let autoLabel = autoRefreshEnabled ? " [Auto-refresh ON]".green : ""
                await terminal.writeLine("═══ Conversation with \(shortAddr.cyan) ═══ \(networkLabel)\(autoLabel)".bold)
                await terminal.writeLine("")

                // Display messages with improved formatting
                for msg in conversation.messages {
                    let time = formatRelativeTime(msg.timestamp)

                    if msg.direction == .sent {
                        // Sent message - right-aligned style
                        await terminal.writeLine("                              \(time.dim)")
                        // Show reply indicator BEFORE the message if this is a reply
                        if let preview = msg.replyContext?.preview {
                            await terminal.writeLine("                    " + "↳ \"\(truncatePreview(preview))\"".dim)
                        }
                        await terminal.writeLine("                    \(msg.content)".green + " [You]".dim)
                    } else {
                        // Received message - left-aligned style
                        await terminal.writeLine("\(time.dim)")
                        // Show reply indicator BEFORE the message if this is a reply
                        if let preview = msg.replyContext?.preview {
                            await terminal.writeLine("↳ \"\(truncatePreview(preview))\"".dim)
                        }
                        await terminal.writeLine("[Them] ".dim + msg.content.blue)
                    }

                    await terminal.writeLine("")
                }

                // Show last refresh time
                let refreshAgo = formatRelativeTime(lastRefreshTime)
                await terminal.writeLine("Last refreshed: \(refreshAgo)".dim)
            }

            // Show action menu - use conversation.lastReceived for easy reply
            var options = ["Send new message"]

            if conversation.lastReceived != nil {
                options.insert("Reply to last message", at: 0)
            }

            // Toggle auto-refresh option
            let autoRefreshOption = autoRefreshEnabled
                ? "⏸ Disable auto-refresh"
                : "▶ Enable auto-refresh"

            options.append(contentsOf: [autoRefreshOption, "Refresh now", "Back"])

            let action = try await terminal.select(
                "Actions",
                options: options
            )

            switch action {
            case "Reply to last message":
                if let original = conversation.lastReceived {
                    if let sentMessage = try await sendReply(chat: chat, conversation: conversation, replyingTo: original, terminal: terminal) {
                        // Append sent message locally for immediate display
                        conversation.append(sentMessage)
                        lastRefreshTime = Date()
                    }
                }
            case "Send new message":
                if let sentMessage = try await sendMessageTo(chat: chat, conversation: conversation, terminal: terminal) {
                    // Append sent message locally for immediate display
                    conversation.append(sentMessage)
                    lastRefreshTime = Date()
                }
            case "▶ Enable auto-refresh":
                autoRefreshEnabled = true
                await terminal.writeLine("Auto-refresh enabled. Messages will refresh each time you return to this screen.".green)
            case "⏸ Disable auto-refresh":
                autoRefreshEnabled = false
                await terminal.writeLine("Auto-refresh disabled.".yellow)
            case "Refresh now":
                let currentConv = conversation
                conversation = try await terminal.withSpinner(
                    message: "Refreshing",
                    style: .dots
                ) {
                    try await chat.refresh(currentConv)
                }
                lastRefreshTime = Date()
            case "Back":
                return
            default:
                break
            }
        }
    }

    static func sendMessageTo(chat: AlgoChat, conversation: Conversation, terminal: Terminal) async throws -> Message? {
        let message = try await terminal.input("Your message (max \(maxMessageBytes) bytes)")

        if message.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return nil
        }

        // Validate message size
        if message.utf8.count > maxMessageBytes {
            await terminal.writeLine("Message too large (max \(maxMessageBytes) bytes).".red)
            return nil
        }

        do {
            // Use .indexed for self-messages to ensure they appear immediately
            let myAddress = await chat.address
            let isSelfMessage = conversation.participant == myAddress
            let sendOptions: SendOptions = isSelfMessage ? .indexed : .confirmed
            let spinnerMessage = isSelfMessage ? "Sending (waiting for indexer)" : "Sending"

            let result = try await terminal.withSpinner(
                message: spinnerMessage,
                style: .dots
            ) {
                try await chat.send(message, to: conversation, options: sendOptions)
            }

            await terminal.writeLine("✅ Sent!".green + " TX: \(String(result.txid.prefix(12)))...".dim)
            if !isLocalnet {
                await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(result.txid)".blue.underline)
            }
            return result.message
        } catch {
            await terminal.writeLine("❌ Failed: \(error.localizedDescription)".red)
            return nil
        }
    }

    static func sendReply(
        chat: AlgoChat,
        conversation: Conversation,
        replyingTo original: Message,
        terminal: Terminal
    ) async throws -> Message? {
        await terminal.writeLine("")
        await terminal.writeLine("Replying to: ".dim + "\"\(truncatePreview(original.content, length: 50))\"".cyan)

        let reply = try await terminal.input("Your reply (max \(maxMessageBytes) bytes)")

        if reply.isEmpty {
            await terminal.writeLine("Cancelled.".yellow)
            return nil
        }

        // Validate message size
        if reply.utf8.count > maxMessageBytes {
            await terminal.writeLine("Reply too large (max \(maxMessageBytes) bytes).".red)
            return nil
        }

        do {
            // Use indexed: true for self-messages to ensure they appear immediately
            let myAddress = await chat.address
            let isSelfMessage = conversation.participant == myAddress
            let spinnerMessage = isSelfMessage ? "Sending reply (waiting for indexer)" : "Sending reply"

            let result = try await terminal.withSpinner(
                message: spinnerMessage,
                style: .dots
            ) {
                try await chat.send(
                    reply,
                    to: conversation,
                    options: .replying(to: original, confirmed: true, indexed: isSelfMessage)
                )
            }

            await terminal.writeLine("✅ Reply sent!".green + " TX: \(String(result.txid.prefix(12)))...".dim)
            if !isLocalnet {
                await terminal.writeLine("Explorer: ".dim + "https://testnet.explorer.perawallet.app/tx/\(result.txid)".blue.underline)
            }
            return result.message
        } catch {
            await terminal.writeLine("❌ Failed: \(error.localizedDescription)".red)
            return nil
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
        var allConversations = try await terminal.withSpinner(
            message: "Fetching conversations",
            style: .dots
        ) {
            try await chat.conversations()
        }

        while true {
            await terminal.writeLine("")
            if allConversations.isEmpty {
                await terminal.writeLine("No conversations yet.".yellow)
                await terminal.writeLine("Send a message to start chatting!".dim)
                return
            }

            let result = try await showConversationList(
                conversations: allConversations,
                chat: chat,
                terminal: terminal,
                searchTerm: nil
            )

            switch result {
            case .back:
                return
            case .refreshAll:
                allConversations = try await terminal.withSpinner(
                    message: "Refreshing all conversations",
                    style: .dots
                ) {
                    try await chat.conversations()
                }
                await terminal.writeLine("✅ Conversations refreshed!".green)
            case .selected:
                // After viewing a conversation, loop back to show list again
                allConversations = try await terminal.withSpinner(
                    message: "Refreshing conversations",
                    style: .dots
                ) {
                    try await chat.conversations()
                }
            }
        }
    }

    enum ConversationListResult {
        case back
        case refreshAll
        case selected
    }

    static func showConversationList(
        conversations: [Conversation],
        chat: AlgoChat,
        terminal: Terminal,
        searchTerm: String?
    ) async throws -> ConversationListResult {
        // Filter conversations if search term provided
        let filtered: [Conversation]
        if let term = searchTerm, !term.isEmpty {
            let lowercased = term.lowercased()
            filtered = conversations.filter { conv in
                conv.participant.description.lowercased().contains(lowercased)
            }
        } else {
            filtered = conversations
        }

        let networkLabel = isLocalnet ? "[Localnet]".yellow : "[TestNet]".cyan
        let searchLabel = searchTerm != nil ? " (filtered)".dim : ""
        await terminal.writeLine("═══ Conversations ═══ \(networkLabel)\(searchLabel)".cyan.bold)
        await terminal.writeLine("")

        if filtered.isEmpty && searchTerm != nil {
            await terminal.writeLine("No conversations matching '\(searchTerm!)'.".yellow)
            await terminal.writeLine("")
        }

        // Build options for selection
        var options: [String] = []

        // Add search and refresh options
        if searchTerm == nil {
            options.append("🔍 Search by address")
        } else {
            options.append("🔍 Clear search")
        }
        options.append("🔄 Refresh all")

        for conv in filtered {
            let shortAddr = truncateAddress(conv.participant.description)
            if let last = conv.lastMessage {
                let time = formatRelativeTime(last.timestamp)
                let who = last.direction == .sent ? "You" : "Them"
                let preview = truncatePreview(last.content)
                options.append("📱 \(shortAddr) (\(conv.messageCount) msgs) - \(who): \(preview) [\(time)]")
            } else {
                options.append("📱 \(shortAddr) (\(conv.messageCount) msgs)")
            }
        }
        options.append("Back")

        let selection = try await terminal.select(
            "Select a conversation",
            options: options
        )

        if selection == "Back" {
            return .back
        }

        if selection == "🔄 Refresh all" {
            return .refreshAll
        }

        if selection == "🔍 Search by address" {
            let term = try await terminal.input("Search (address substring)")
            if !term.isEmpty {
                return try await showConversationList(
                    conversations: conversations,
                    chat: chat,
                    terminal: terminal,
                    searchTerm: term
                )
            } else {
                return try await showConversationList(
                    conversations: conversations,
                    chat: chat,
                    terminal: terminal,
                    searchTerm: nil
                )
            }
        }

        if selection == "🔍 Clear search" {
            return try await showConversationList(
                conversations: conversations,
                chat: chat,
                terminal: terminal,
                searchTerm: nil
            )
        }

        // Find the selected conversation (convert to Array for zero-based indexing)
        let conversationOptions = Array(options.dropFirst(2).dropLast()) // Remove search, refresh, and Back
        if let index = conversationOptions.firstIndex(of: selection) {
            let conv = filtered[index]
            try await viewConversation(chat: chat, participant: conv.participant, terminal: terminal)
            return .selected
        }

        return .back
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

        // Show key fingerprint for easy verification
        let fingerprint = SignatureVerifier.fingerprint(of: pubKey)
        await terminal.writeLine("Key Fingerprint:".dim)
        await terminal.writeLine("  \(fingerprint)".yellow)
        await terminal.writeLine("")

        // Check if key is saved
        #if os(iOS) || os(macOS) || os(visionOS)
        let hasSavedKey = await account.hasStoredEncryptionKey(in: keyStorage)
        if hasSavedKey {
            let biometric = KeychainKeyStorage.biometricType.rawValue
            await terminal.writeLine("Key Storage:".dim)
            await terminal.writeLine("  🔐 Protected by \(biometric)".green)
            await terminal.writeLine("")
        }
        #else
        let hasSavedKey = await account.hasStoredEncryptionKey(in: fileKeyStorage)
        if hasSavedKey {
            await terminal.writeLine("Key Storage:".dim)
            await terminal.writeLine("  🔐 Password-protected (~/.algochat/keys/)".green)
            await terminal.writeLine("")
        }
        #endif

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
        guard let dockerPath = findDockerPath() else {
            throw FundingError.failed("Docker not found. Install Docker Desktop or ensure docker is in your PATH.")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: dockerPath)
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

            guard let dockerPath = findDockerPath() else {
                throw FundingError.failed("Docker not found")
            }

            try await terminal.withSpinner(
                message: "Sending 10 ALGO",
                style: .dots
            ) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: dockerPath)
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
