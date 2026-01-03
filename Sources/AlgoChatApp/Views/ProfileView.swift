import AlgoChat
import Algorand
import SwiftUI

struct ProfileView: View {
    let address: String
    @EnvironmentObject private var contactsStore: ContactsStore
    @EnvironmentObject private var appState: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String = ""
    @State private var showCopied = false
    @State private var keyFingerprint: String?
    @State private var isKeyVerified: Bool = false
    @State private var isLoadingKey = false

    private var contact: Contact? {
        contactsStore.contact(for: address)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Avatar
                    HStack {
                        Spacer()
                        Circle()
                            .fill(avatarColor)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text(avatarInitial)
                                    .font(.largeTitle)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                            }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Contact name", text: $editedName)
                        .onSubmit {
                            saveName()
                        }
                }

                Section("Address") {
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

                Section {
                    if isLoadingKey {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading key...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let fingerprint = keyFingerprint {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(fingerprint)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            if isKeyVerified {
                                Label("Verified", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Label("Unverified (legacy key)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("No encryption key found")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Encryption Key")
                } footer: {
                    if keyFingerprint != nil {
                        Text(isKeyVerified
                            ? "This key was cryptographically signed by the account owner."
                            : "This key was not signed. Verify fingerprint out-of-band for sensitive communications."
                        )
                    }
                }

                Section {
                    Button {
                        contactsStore.toggleFavorite(address: address)
                    } label: {
                        Label(
                            contactsStore.isFavorite(address: address) ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: contactsStore.isFavorite(address: address) ? "star.fill" : "star"
                        )
                    }

                    if contact != nil {
                        Button(role: .destructive) {
                            if let contact {
                                contactsStore.remove(contact)
                            }
                            dismiss()
                        } label: {
                            Label("Remove Contact", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(contact?.displayName ?? truncatedAddress)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveName()
                        dismiss()
                    }
                }
            }
            .onAppear {
                editedName = contact?.name ?? ""
                fetchEncryptionKey()
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 400)
        #endif
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

    private func saveName() {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            contactsStore.rename(address: address, to: name)
        }
    }

    private func fetchEncryptionKey() {
        guard let chat = appState.chat else { return }

        Task {
            isLoadingKey = true
            defer { isLoadingKey = false }

            do {
                let address = try Algorand.Address(string: address)
                let publicKey = try await chat.fetchPublicKey(for: address)

                // Generate fingerprint
                keyFingerprint = SignatureVerifier.fingerprint(of: publicKey.rawRepresentation)

                // Check if the conversation has a verified key
                // For now, we can't easily determine if the key was verified during discovery
                // so we'll mark as verified if we have the key (future: track verification status)
                isKeyVerified = false  // TODO: Track verification status from key discovery
            } catch {
                keyFingerprint = nil
                isKeyVerified = false
            }
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

// MARK: - Contacts List View

struct ContactsListView: View {
    @EnvironmentObject private var contactsStore: ContactsStore
    @EnvironmentObject private var appState: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddContact = false
    @State private var selectedContact: Contact?

    var body: some View {
        NavigationStack {
            List {
                if !contactsStore.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(contactsStore.favorites) { contact in
                            ContactRow(contact: contact)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    startConversation(with: contact.address)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        contactsStore.remove(contact)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        contactsStore.toggleFavorite(contact)
                                    } label: {
                                        Label("Unfavorite", systemImage: "star.slash")
                                    }
                                    .tint(.yellow)
                                }
                        }
                    }
                }

                let nonFavorites = contactsStore.contacts.filter { !$0.isFavorite }
                if !nonFavorites.isEmpty {
                    Section("Contacts") {
                        ForEach(nonFavorites.sorted { $0.name < $1.name }) { contact in
                            ContactRow(contact: contact)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    startConversation(with: contact.address)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        contactsStore.remove(contact)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        contactsStore.toggleFavorite(contact)
                                    } label: {
                                        Label("Favorite", systemImage: "star.fill")
                                    }
                                    .tint(.yellow)
                                }
                        }
                    }
                }

                if contactsStore.contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add contacts to quickly start conversations")
                    )
                }
            }
            .navigationTitle("Contacts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddContact = true
                    } label: {
                        Label("Add Contact", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddContact) {
                AddContactView()
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 500)
        #endif
    }

    private func startConversation(with address: String) {
        Task {
            let success = await appState.startNewConversation(with: address)
            if success {
                dismiss()
            }
        }
    }
}

struct ContactRow: View {
    let contact: Contact
    @EnvironmentObject private var contactsStore: ContactsStore
    @State private var showProfile = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarColor)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(avatarInitial)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(contact.displayName)
                        .font(.headline)

                    if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                Text(contact.truncatedAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showProfile = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(address: contact.address)
        }
    }

    private var avatarInitial: String {
        String(contact.displayName.prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        let hash = contact.address.hashValue
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return colors[abs(hash) % colors.count]
    }
}

struct AddContactView: View {
    @EnvironmentObject private var contactsStore: ContactsStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var name = ""

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
                    Text("Address")
                } footer: {
                    Text("Enter the 58-character Algorand address")
                }

                Section("Name (Optional)") {
                    TextField("Contact name", text: $name)
                }
            }
            .navigationTitle("Add Contact")
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
                    Button("Add") {
                        contactsStore.add(address: address, name: name)
                        dismiss()
                    }
                    .disabled(address.count < 58)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 250)
        #endif
    }
}

#Preview {
    ProfileView(address: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        .environmentObject(ContactsStore())
        .environmentObject(ApplicationState())
}
