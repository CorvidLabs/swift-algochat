import AlgoChat
import Algorand
import AlgoKit
import Combine
import SwiftUI

@MainActor
final class ApplicationState: ObservableObject {
    // MARK: - Published State

    @Published var isLoading = false
    @Published var error: AppError?
    @Published var conversations: [Conversation] = []
    @Published var selectedConversation: Conversation?
    @Published var accountBalance: MicroAlgos?
    @Published private(set) var savedAccounts: [SavedAccount] = []

    // MARK: - Chat Client

    private(set) var chat: AlgoChat?
    private(set) var currentAddress: Address?
    private(set) var currentNetwork: AlgorandConfiguration.Network = .testnet
    private(set) var currentMnemonic: String?

    // MARK: - Storage

    private let accountStorage = AccountStorage()

    // MARK: - Configuration

    var isConnected: Bool { chat != nil }

    // MARK: - Initialization

    func connect(mnemonic: String, network: AlgorandConfiguration.Network = .testnet) async {
        isLoading = true
        error = nil

        do {
            let account = try Account(mnemonic: mnemonic)
            let chatClient = try await AlgoChat(network: network, account: account)
            self.chat = chatClient
            self.currentAddress = await chatClient.address
            self.currentNetwork = network
            self.currentMnemonic = mnemonic

            // Load initial data
            await loadConversations()
            await refreshBalance()
        } catch {
            self.error = AppError(message: "Failed to connect: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func disconnect() {
        chat = nil
        currentAddress = nil
        currentMnemonic = nil
        conversations = []
        selectedConversation = nil
        accountBalance = nil
    }

    // MARK: - Saved Accounts

    /// Loads saved accounts from storage (does not trigger biometric)
    func loadSavedAccounts() async {
        savedAccounts = await accountStorage.listAccounts()
    }

    /// Connects using a saved account (triggers biometric authentication)
    func connectSaved(_ account: SavedAccount) async {
        isLoading = true
        error = nil

        do {
            let mnemonic = try await accountStorage.retrieveMnemonic(for: account)
            let network: AlgorandConfiguration.Network
            switch account.network {
            case "mainnet":
                network = .mainnet
            case "localnet":
                network = .localnet
            default:
                network = .testnet
            }

            let algorandAccount = try Account(mnemonic: mnemonic)
            let chatClient = try await AlgoChat(network: network, account: algorandAccount)

            self.chat = chatClient
            self.currentAddress = await chatClient.address
            self.currentNetwork = network
            self.currentMnemonic = mnemonic

            // Update last used timestamp
            await accountStorage.updateLastUsed(for: account.address)
            await loadSavedAccounts()

            // Load initial data
            await loadConversations()
            await refreshBalance()
        } catch let storageError as AccountStorageError {
            switch storageError {
            case .biometricCanceled:
                // User canceled - don't show error
                break
            default:
                self.error = AppError(message: storageError.localizedDescription)
            }
        } catch {
            self.error = AppError(message: "Failed to connect: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Saves the current account with biometric protection
    func saveCurrentAccount(name: String? = nil) async throws {
        guard let address = currentAddress,
              let mnemonic = currentMnemonic else {
            throw AccountStorageError.invalidMnemonic
        }

        let networkString: String
        switch currentNetwork {
        case .mainnet:
            networkString = "mainnet"
        case .testnet:
            networkString = "testnet"
        case .localnet:
            networkString = "localnet"
        case .custom:
            networkString = "custom"
        }

        try await accountStorage.save(
            mnemonic: mnemonic,
            for: address.description,
            network: networkString,
            name: name
        )

        await loadSavedAccounts()
    }

    /// Deletes a saved account
    func deleteSavedAccount(_ account: SavedAccount) async throws {
        try await accountStorage.delete(for: account)
        await loadSavedAccounts()
    }

    /// Updates the display name for a saved account
    func renameSavedAccount(_ account: SavedAccount, to name: String?) async {
        await accountStorage.updateName(for: account.address, name: name)
        await loadSavedAccounts()
    }

    /// Checks if the current account is saved
    var isCurrentAccountSaved: Bool {
        guard let address = currentAddress else { return false }
        return savedAccounts.contains { $0.address == address.description }
    }

    /// Gets the saved account for the current address
    var currentSavedAccount: SavedAccount? {
        guard let address = currentAddress else { return nil }
        return savedAccounts.first { $0.address == address.description }
    }

    // MARK: - Conversations

    func loadConversations() async {
        guard let chat else { return }

        do {
            let convos = try await chat.conversations(limit: 100)
            self.conversations = convos.sorted {
                ($0.lastMessage?.timestamp ?? .distantPast) > ($1.lastMessage?.timestamp ?? .distantPast)
            }
        } catch {
            self.error = AppError(message: "Failed to load conversations: \(error.localizedDescription)")
        }
    }

    func selectConversation(_ conversation: Conversation) async {
        selectedConversation = conversation

        // Refresh the conversation to get latest messages
        await refreshSelectedConversation()
    }

    func refreshSelectedConversation() async {
        guard let chat, var conversation = selectedConversation else { return }

        do {
            conversation = try await chat.refresh(conversation, limit: 50)
            selectedConversation = conversation

            // Update in the list too
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = conversation
            }
        } catch {
            self.error = AppError(message: "Failed to refresh: \(error.localizedDescription)")
        }
    }

    func startNewConversation(with addressString: String) async -> Bool {
        guard let chat else { return false }

        do {
            let address = try Address(string: addressString)
            var conversation = try await chat.conversation(with: address)

            // Try to refresh to get any existing messages
            conversation = try await chat.refresh(conversation, limit: 50)

            // Add to list if not already present
            if !conversations.contains(where: { $0.id == conversation.id }) {
                conversations.insert(conversation, at: 0)
            }

            selectedConversation = conversation
            return true
        } catch {
            self.error = AppError(message: "Invalid address: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Messaging

    func sendMessage(_ text: String, replyTo: Message? = nil) async -> Bool {
        guard let chat, var conversation = selectedConversation else { return false }

        do {
            let options: SendOptions
            if let replyTo {
                options = .replying(to: replyTo, confirmed: true)
            } else {
                options = .confirmed
            }

            let result = try await chat.send(text, to: conversation, options: options)
            conversation.append(result.message)
            selectedConversation = conversation

            // Update in the list
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = conversation
            }

            // Re-sort conversations by most recent
            conversations.sort {
                ($0.lastMessage?.timestamp ?? .distantPast) > ($1.lastMessage?.timestamp ?? .distantPast)
            }

            return true
        } catch {
            self.error = AppError(message: "Failed to send: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Account

    func refreshBalance() async {
        guard let chat else { return }

        do {
            accountBalance = try await chat.balance()
        } catch {
            // Silently fail for balance refresh
        }
    }

    func publishKey() async -> Bool {
        guard let chat else { return false }

        do {
            _ = try await chat.publishKeyAndWait()
            return true
        } catch {
            self.error = AppError(message: "Failed to publish key: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Error Handling

    func clearError() {
        error = nil
    }
}

// MARK: - App Error

struct AppError: Identifiable {
    let id = UUID()
    let message: String
}
