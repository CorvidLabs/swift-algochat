import AlgoChat
import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var appState: ApplicationState
    @State private var showNewConversation = false
    @State private var isRefreshing = false

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedConversation },
            set: { conversation in
                if let conversation {
                    Task { await appState.selectConversation(conversation) }
                }
            }
        )) {
            ForEach(appState.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showNewConversation = true
                } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }

                Button {
                    Task {
                        isRefreshing = true
                        await appState.loadConversations()
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)

                Menu {
                    if let address = appState.currentAddress {
                        Text(address.description)
                            .font(.caption)
                    }

                    if let balance = appState.accountBalance {
                        Text("Balance: \(balance.algos, specifier: "%.4f") ALGO")
                    }

                    Divider()

                    Button("Publish Key") {
                        Task { await appState.publishKey() }
                    }

                    Button("Disconnect", role: .destructive) {
                        appState.disconnect()
                    }
                } label: {
                    Label("Account", systemImage: "person.circle")
                }
            }
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationView()
        }
        .refreshable {
            await appState.loadConversations()
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(avatarInitial)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(truncatedAddress)
                    .font(.headline)
                    .lineLimit(1)

                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }

            Spacer()

            if let lastMessage = conversation.lastMessage {
                Text(formatTimestamp(lastMessage.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var truncatedAddress: String {
        let addr = conversation.participant.description
        if addr.count > 12 {
            return "\(addr.prefix(6))...\(addr.suffix(4))"
        }
        return addr
    }

    private var avatarInitial: String {
        String(conversation.participant.description.prefix(1))
    }

    private var avatarColor: Color {
        let hash = conversation.participant.description.hashValue
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return colors[abs(hash) % colors.count]
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

struct NewConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: ApplicationState
    @State private var address = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Algorand Address", text: $address)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Recipient")
                } footer: {
                    Text("Enter the 58-character Algorand address of the person you want to message.")
                }
            }
            .navigationTitle("New Conversation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task {
                            isCreating = true
                            let success = await appState.startNewConversation(with: address)
                            isCreating = false
                            if success {
                                dismiss()
                            }
                        }
                    }
                    .disabled(address.count < 58 || isCreating)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 200)
        #endif
    }
}

#Preview {
    NavigationStack {
        ConversationListView()
            .environmentObject(ApplicationState())
    }
}
