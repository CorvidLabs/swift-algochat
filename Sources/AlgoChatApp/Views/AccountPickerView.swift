import SwiftUI

/// View for selecting and unlocking saved accounts
struct AccountPickerView: View {
    @EnvironmentObject private var appState: ApplicationState
    @State private var showingNewAccount = false

    private var biometricName: String {
        AccountStorage.biometricType.rawValue
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.savedAccounts) { account in
                        AccountRow(account: account) {
                            Task {
                                await appState.connectSaved(account)
                            }
                        }
                    }
                    .onDelete(perform: deleteAccounts)
                } header: {
                    if !appState.savedAccounts.isEmpty {
                        Text("Saved Accounts")
                    }
                } footer: {
                    if !appState.savedAccounts.isEmpty {
                        Text("Tap to unlock with \(biometricName). Swipe to delete.")
                    }
                }

                Section {
                    Button {
                        showingNewAccount = true
                    } label: {
                        Label("Use Different Account", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("AlgoChat")
            .overlay {
                if appState.isLoading {
                    ProgressView("Authenticating...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showingNewAccount) {
                NavigationStack {
                    LoginView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    showingNewAccount = false
                                }
                            }
                        }
                }
            }
            #else
            .sheet(isPresented: $showingNewAccount) {
                NavigationStack {
                    LoginView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    showingNewAccount = false
                                }
                            }
                        }
                }
                .frame(minWidth: 500, minHeight: 600)
            }
            #endif
            .alert(
                "Error",
                isPresented: Binding(
                    get: { appState.error != nil },
                    set: { if !$0 { appState.clearError() } }
                ),
                presenting: appState.error
            ) { _ in
                Button("OK") { appState.clearError() }
            } message: { error in
                Text(error.message)
            }
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let account = appState.savedAccounts[index]
                try? await appState.deleteSavedAccount(account)
            }
        }
    }
}

// MARK: - Account Row

private struct AccountRow: View {
    let account: SavedAccount
    let onTap: () -> Void

    private var networkBadge: some View {
        Text(account.network.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(account.network == "mainnet" ? Color.green : Color.orange)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var biometricIcon: String {
        switch AccountStorage.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "key"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: biometricIcon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(account.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        networkBadge
                    }

                    Text(account.truncatedAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AccountPickerView()
        .environmentObject(ApplicationState())
}
