import AlgoChat
import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var appState: ApplicationState
    @EnvironmentObject private var contactsStore: ContactsStore
    @State private var showNewConversation = false
    @State private var showContacts = false
    @State private var showMyProfile = false
    @State private var showAccountSettings = false
    @State private var isRefreshing = false

    private var favoriteConversations: [Conversation] {
        appState.conversations.filter { contactsStore.isFavorite(address: $0.participant.description) }
    }

    private var otherConversations: [Conversation] {
        appState.conversations.filter { !contactsStore.isFavorite(address: $0.participant.description) }
    }

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedConversation },
            set: { conversation in
                if let conversation {
                    Task { await appState.selectConversation(conversation) }
                }
            }
        )) {
            if !favoriteConversations.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteConversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(conversation)
                    }
                }
            }

            Section(favoriteConversations.isEmpty ? "Messages" : "Other") {
                ForEach(otherConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(conversation)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showContacts = true
                } label: {
                    Label("Contacts", systemImage: "person.2")
                }

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
                    Button {
                        showMyProfile = true
                    } label: {
                        Label("My Profile", systemImage: "person.crop.circle")
                    }

                    Button {
                        showAccountSettings = true
                    } label: {
                        Label("Account Settings", systemImage: "gearshape")
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
        .sheet(isPresented: $showContacts) {
            ContactsListView()
        }
        .sheet(isPresented: $showMyProfile) {
            MyProfileView()
        }
        .sheet(isPresented: $showAccountSettings) {
            AccountSettingsView()
        }
        .refreshable {
            await appState.loadConversations()
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @EnvironmentObject private var contactsStore: ContactsStore
    @State private var showProfile = false

    private var address: String {
        conversation.participant.description
    }

    private var contact: Contact? {
        contactsStore.contact(for: address)
    }

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
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if contactsStore.isFavorite(address: address) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

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

            VStack(alignment: .trailing, spacing: 4) {
                if let lastMessage = conversation.lastMessage {
                    Text(formatTimestamp(lastMessage.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                contactsStore.toggleFavorite(address: address)
            } label: {
                Label(
                    contactsStore.isFavorite(address: address) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: contactsStore.isFavorite(address: address) ? "star.slash" : "star"
                )
            }

            Button {
                showProfile = true
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }

            Button {
                copyToClipboard(address)
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(address: address)
        }
    }

    private var displayName: String {
        contact?.displayName ?? truncatedAddress
    }

    private var truncatedAddress: String {
        if address.count > 12 {
            return "\(address.prefix(6))...\(address.suffix(4))"
        }
        return address
    }

    private var avatarInitial: String {
        if let name = contact?.name, !name.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return String(address.prefix(1))
    }

    private var avatarColor: Color {
        let hash = address.hashValue
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

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

struct NewConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: ApplicationState
    @EnvironmentObject private var contactsStore: ContactsStore
    @State private var address = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                if !contactsStore.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(contactsStore.favorites) { contact in
                            Button {
                                startConversation(with: contact.address)
                            } label: {
                                HStack {
                                    Text(contact.displayName)
                                    Spacer()
                                    Text(contact.truncatedAddress)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Algorand Address", text: $address)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Or enter address")
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
                        startConversation(with: address)
                    }
                    .disabled(address.count < 58 || isCreating)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 350)
        #endif
    }

    private func startConversation(with addr: String) {
        Task {
            isCreating = true
            let success = await appState.startNewConversation(with: addr)
            isCreating = false
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - My Profile View

struct MyProfileView: View {
    @EnvironmentObject private var appState: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var showCopied = false

    private var address: String {
        appState.currentAddress?.description ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.white)
                            }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("My Address") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(address)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Button {
                            copyToClipboard(address)
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopied = false
                            }
                        } label: {
                            Label(showCopied ? "Copied!" : "Copy Address", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let balance = appState.accountBalance {
                    Section("Balance") {
                        Text("\(balance.algos, specifier: "%.4f") ALGO")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }

                Section {
                    Button("Publish Key") {
                        Task { await appState.publishKey() }
                    }

                    Button("Refresh Balance") {
                        Task { await appState.refreshBalance() }
                    }
                }
            }
            .navigationTitle("My Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 450)
        #endif
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#Preview {
    NavigationStack {
        ConversationListView()
            .environmentObject(ApplicationState())
            .environmentObject(ContactsStore())
    }
}
