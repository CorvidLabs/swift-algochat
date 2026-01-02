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

    // MARK: - Chat Client

    private(set) var chat: AlgoChat?
    private(set) var currentAddress: Address?

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
        conversations = []
        selectedConversation = nil
        accountBalance = nil
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
